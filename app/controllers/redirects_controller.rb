# Handles affiliate redirects with click tracking
class RedirectsController < ApplicationController
  def smd
    smd_id = params[:smd_id]

    # Validate: must be numeric (SMD product IDs are integers)
    unless smd_id.present? && smd_id.match?(/\A\d+\z/)
      head :bad_request
      return
    end

    # Reject direct hits without a valid referrer from this site
    # (bots hitting /go/smd/ directly without visiting a score page)
    unless valid_internal_referrer?
      head :forbidden
      return
    end

    # Track the click (skip bots and prefetch)
    unless bot? || prefetch?
      score = Score.find_by(external_id: smd_id, source: "smd")
      DailyStat.track_smd_click!(score_id: score.id) if score
    end

    # 302 (not 301) - temporary redirect so we can change affiliate ID or tracking later
    redirect_to smd_product_url(smd_id), allow_other_host: true
  end

  private

  def valid_internal_referrer?
    return false if request.referer.blank?

    ref_host = URI.parse(request.referer).host rescue nil
    ref_host.present? && ref_host == request.host
  end

  def smd_product_url(smd_id)
    "https://www.sheetmusicdirect.com/se/ID_No/#{smd_id}/Product.aspx?affiliate=#{Score::SMD_AFFILIATE_ID}"
  end
end
