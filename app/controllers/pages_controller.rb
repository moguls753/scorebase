class PagesController < ApplicationController
  allow_unauthenticated_access

  def about
    @total_count = Score.count
    @source_counts = Score.group(:source).count
  end

  def impressum
  end

  def pro
    @total_count = Score.count
  end
end
