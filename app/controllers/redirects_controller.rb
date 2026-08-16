# Centralizes the affiliate IDs behind a robots-disallowed /go/ redirect.
class RedirectsController < ApplicationController
  NUMERIC_ID = /\A\d+\z/

  # Stretta's slug is read from our own row, never from the URL: a /go/stretta/*slug
  # route would be a path injection into stretta-music.de. Checked anyway, because
  # the value travels through an importer.
  SAFE_SLUG = /\A[a-z0-9][a-z0-9-]*\z/

  def smd
    smd_id = params[:smd_id]

    # Validate: must be numeric (SMD product IDs are integers)
    unless smd_id.present? && smd_id.match?(NUMERIC_ID)
      head :bad_request
      return
    end

    # Reject direct hits without a valid referrer from this site
    # (bots hitting /go/smd/ directly without visiting a score page)
    unless valid_internal_referrer?
      head :forbidden
      return
    end

    # The buy click is tracked client-side (buy_redirect_controller.js) so only
    # real user clicks count — a bare GET to /go/ (bots/prefetch) must not track.
    # 302 (not 301) - temporary redirect so we can change affiliate ID or tracking later
    redirect_to smd_product_url(smd_id), allow_other_host: true
  end

  # Measured 2026-08-15 against the live shop: the slug URL answers 200 and keeps
  # ?afl=, while /x-nr-<id>.html answers 301 to the slug URL *without* the query
  # string — that form silently drops the affiliate code, and with settlement only
  # in February the loss would go unnoticed for half a year.
  def stretta
    id = params[:id]

    unless id.present? && id.match?(NUMERIC_ID)
      head :bad_request
      return
    end

    unless valid_internal_referrer?
      head :forbidden
      return
    end

    slug = Score.where(source: "stretta", external_id: id).pick(:partner_slug)
    unless slug.present? && slug.match?(SAFE_SLUG)
      head :not_found
      return
    end

    redirect_to stretta_product_url(slug), allow_other_host: true
  end

  private

  # Depends on the Referer header being sent — a global Referrer-Policy: no-referrer would 403 every buy click.
  def valid_internal_referrer?
    return false if request.referer.blank?

    ref_host = URI.parse(request.referer).host rescue nil
    ref_host.present? && ref_host == request.host
  end

  def smd_product_url(smd_id)
    "https://www.sheetmusicdirect.com/se/ID_No/#{smd_id}/Product.aspx?affiliate=#{Score::SMD_AFFILIATE_ID}"
  end

  def stretta_product_url(slug)
    "https://www.stretta-music.de/#{slug}.html?afl=#{Score::STRETTA_AFFILIATE_ID}"
  end
end
