class Avo::ScoresController < Avo::ResourcesController
  # Override destroy to soft delete instead of hard delete
  def destroy
    @record = Score.find(params[:id])
    @record.soft_delete!

    redirect_to resources_scores_path, notice: "Score moved to trash. Can be restored within 100 days."
  end
end
