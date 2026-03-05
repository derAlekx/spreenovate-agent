module StepExecutors
  class HumanReview < Base
    def execute
      item.update!(status: "review")
    end
  end
end
