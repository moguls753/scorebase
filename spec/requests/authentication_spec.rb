# Authentication - Critical User Flows
#
# Tests the auth system works end-to-end.
# Following TESTING_APPROACH.md: test business logic and critical paths.

require 'rails_helper'

RSpec.describe "Authentication", type: :request do
  describe "Sign up" do
    it "creates a user with valid credentials" do
      expect {
        post user_path, params: {
          user: {
            email_address: "new@example.com",
            password: "password123",
            password_confirmation: "password123"
          }
        }
      }.to change(User, :count).by(1)

      expect(response).to redirect_to(root_path)
      follow_redirect!
      expect(response).to be_successful
    end

    it "rejects invalid email" do
      expect {
        post user_path, params: {
          user: {
            email_address: "not-an-email",
            password: "password123",
            password_confirmation: "password123"
          }
        }
      }.not_to change(User, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "rejects short password" do
      expect {
        post user_path, params: {
          user: {
            email_address: "new@example.com",
            password: "short",
            password_confirmation: "short"
          }
        }
      }.not_to change(User, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "Sign in" do
    let!(:user) { create(:user, email_address: "test@example.com", password: "password123") }

    it "signs in with valid credentials" do
      post session_path, params: {
        email_address: "test@example.com",
        password: "password123"
      }

      expect(response).to redirect_to(root_path)
      expect(cookies[:session_id]).to be_present
    end

    it "rejects invalid password" do
      post session_path, params: {
        email_address: "test@example.com",
        password: "wrong_password"
      }

      expect(response).to redirect_to(new_session_path)
      expect(cookies[:session_id]).to be_blank
    end

    it "rejects unknown email" do
      post session_path, params: {
        email_address: "unknown@example.com",
        password: "password123"
      }

      expect(response).to redirect_to(new_session_path)
    end
  end

  describe "Sign out" do
    let!(:user) { create(:user) }

    it "destroys the session" do
      # Sign in first
      post session_path, params: {
        email_address: user.email_address,
        password: "password123"
      }
      expect(response).to redirect_to(root_path)

      # Sign out
      delete session_path

      expect(response).to redirect_to(new_session_path)
    end
  end

  describe "Smart Search access control" do
    it "redirects unauthenticated users to sign in" do
      get smart_search_path

      expect(response).to redirect_to(new_session_path)
    end

    it "allows authenticated users with remaining searches" do
      user = create(:user)
      post session_path, params: {
        email_address: user.email_address,
        password: "password123"
      }

      get smart_search_path

      expect(response).to be_successful
    end

    it "shows limit reached page when free searches exhausted" do
      user = create(:user, smart_search_count: 3)
      post session_path, params: {
        email_address: user.email_address,
        password: "password123"
      }

      get smart_search_path

      expect(response).to be_successful
      expect(response.body).to include("used your free searches")
    end

    it "allows pro users" do
      user = create(:user, :pro)
      post session_path, params: {
        email_address: user.email_address,
        password: "password123"
      }

      get smart_search_path

      expect(response).to be_successful
    end

    it "increments search count on search" do
      user = create(:user)
      post session_path, params: {
        email_address: user.email_address,
        password: "password123"
      }

      expect {
        get smart_search_path, params: { q: "easy bach" }
      }.to change { user.reload.smart_search_count }.by(1)
    end
  end

  describe "Password reset" do
    let!(:user) { create(:user, email_address: "reset@example.com") }

    it "sends reset email for existing user" do
      expect {
        post passwords_path, params: { email_address: "reset@example.com" }
      }.to have_enqueued_mail(PasswordsMailer, :reset)

      expect(response).to redirect_to(new_session_path)
    end

    it "shows same response for non-existent email (no enumeration)" do
      expect {
        post passwords_path, params: { email_address: "unknown@example.com" }
      }.not_to have_enqueued_mail(PasswordsMailer, :reset)

      expect(response).to redirect_to(new_session_path)
    end

    it "resets password with valid token" do
      token = user.password_reset_token

      patch password_path(token), params: {
        password: "newpassword123",
        password_confirmation: "newpassword123"
      }

      expect(response).to redirect_to(new_session_path)

      # Can sign in with new password
      post session_path, params: {
        email_address: "reset@example.com",
        password: "newpassword123"
      }
      expect(response).to redirect_to(root_path)
    end

    it "rejects invalid token" do
      get edit_password_path("invalid-token")

      expect(response).to redirect_to(new_password_path)
    end

    it "destroys all sessions after password reset" do
      # Create a session
      post session_path, params: {
        email_address: user.email_address,
        password: "password123"
      }
      expect(user.sessions.count).to eq(1)

      # Reset password
      token = user.password_reset_token
      patch password_path(token), params: {
        password: "newpassword123",
        password_confirmation: "newpassword123"
      }

      expect(user.sessions.reload.count).to eq(0)
    end
  end
end
