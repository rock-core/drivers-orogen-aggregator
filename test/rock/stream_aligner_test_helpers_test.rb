# frozen-string-literal: true

require "rock/stream_aligner_test_helpers"
import_types_from "base"

describe Syskit.Aggregator.TestHelpers do
    run_live

    attr_reader :task

    before do
        task_m = @task_m = Syskit::TaskContext.new_submodel do
            output_port "value_port", "/double"
            output_port "transformer_stream_aligner_status_port", "/double"
        end

        @task = syskit_stub_deploy_and_start(@task_m)
    end

    it "writes an aligned sample" do
        stream_aligner_write(@task, @task.value_port, 42, time_field: "timestamp")
    end
end
