class PagesController < ApplicationController
  def about
    @total_count = Score.count
    @source_counts = Score.group(:source).count
  end

  def impressum
  end

  def pro
    # Pro landing page with waitlist form
    # Waitlist implementation: see WaitlistSignupsController and WaitlistMailer
    @total_count = Score.count
  end
end
