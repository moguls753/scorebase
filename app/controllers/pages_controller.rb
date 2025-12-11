class PagesController < ApplicationController
  def about
    @total_count = Score.count
    @source_counts = Score.group(:source).count
  end

  def impressum
  end
end
