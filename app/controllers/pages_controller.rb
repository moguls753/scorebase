class PagesController < ApplicationController
  def about
    @total_count = Score.count
    @source_counts = Score.group(:source).count
  end

  def impressum
  end

  def pro
    # Pro landing page / waitlist
    # TODO: Wire up waitlist form to email service (Mailchimp, ConvertKit, etc)
  end
end
