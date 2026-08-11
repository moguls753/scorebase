# frozen_string_literal: true

require "rails_helper"

# A job whose queue has no worker in config/queue.yml enqueues fine and then sits
# there forever — no error, no retry, nothing in the logs. NormalizeComposersJob
# and NormalizePeriodsJob both shipped on a :normalization queue that production
# never worked. This pins the invariant rather than the one incident.
RSpec.describe "Solid Queue worker coverage" do
  let(:worked_queues) do
    config = YAML.load_file(Rails.root.join("config/queue.yml"), aliases: true).fetch("production")
    config.fetch("workers").flat_map { |worker| Array(worker["queues"]) }
  end

  # Gem-supplied jobs (e.g. Sentry::SendEventJob) are out of our hands, and some
  # resolve queue_name lazily via a lambda. Only assert on jobs we define.
  def our_own?(job)
    source = Object.const_source_location(job.name)&.first
    source&.start_with?(Rails.root.join("app/jobs").to_s)
  end

  it "has a production worker for every queue a job enqueues to" do
    Rails.application.eager_load!

    declared = ApplicationJob.descendants.select { |job| our_own?(job) }
                             .to_h { |job| [ job.name, job.queue_name.to_s ] }
    expect(declared).not_to be_empty, "no job classes found — did eager loading fail?"

    uncovered = declared.reject { |_, queue| worked_queues.include?(queue) || worked_queues.include?("*") }

    expect(uncovered).to be_empty,
      "these jobs enqueue to queues no production worker processes: " \
      "#{uncovered.map { |job, q| "#{job} -> #{q}" }.join(', ')}. " \
      "Add a worker in config/queue.yml or move the job to a worked queue."
  end
end

# A recurring entry naming a class that does not exist, or a queue nobody works,
# fails the same silent way: Solid Queue schedules it and nothing ever runs.
RSpec.describe "Recurring schedule" do
  let(:schedule) do
    YAML.load_file(Rails.root.join("config/recurring.yml"), aliases: true).fetch("production")
  end

  let(:worked_queues) do
    config = YAML.load_file(Rails.root.join("config/queue.yml"), aliases: true).fetch("production")
    config.fetch("workers").flat_map { |worker| Array(worker["queues"]) }
  end

  # An unparseable schedule is worse than a silent no-op: Supervisor.start aborts, taking down every
  # queue in the job container, not just the offending entry.
  it "gives every entry a schedule Solid Queue can parse" do
    schedule.each do |name, entry|
      expect(Fugit.parse(entry["schedule"])).to be_a(Fugit::Cron),
        "recurring entry '#{name}' has an unparseable schedule: #{entry['schedule'].inspect}"
    end
  end

  it "names classes that exist, on queues that are worked, with arguments perform accepts" do
    schedule.each do |name, entry|
      next unless entry["class"]

      klass = entry["class"].safe_constantize
      expect(klass).to be_present, "recurring entry '#{name}' names a class that does not exist: #{entry['class']}"

      queue = entry["queue"] || klass.queue_name.to_s
      expect(worked_queues).to include(queue).or(include("*")),
        "recurring entry '#{name}' targets queue '#{queue}', which no production worker processes"

      # Guards the args shape: keyword-only perform methods need a trailing hash.
      keywords = klass.instance_method(:perform).parameters.select { |type, _| [ :key, :keyreq ] .include?(type) }
      next if keywords.empty? || entry["args"].blank?

      supplied = entry["args"].last
      expect(supplied).to be_a(Hash),
        "recurring entry '#{name}' passes positional args, but #{klass}#perform takes keywords"
      expect(supplied.keys.map(&:to_sym)).to all(be_in(keywords.map(&:last))),
        "recurring entry '#{name}' passes unknown keywords to #{klass}#perform"
    end
  end
end
