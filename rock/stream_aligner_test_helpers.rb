# frozen-string-literal: true

# no-doc
module Syskit
    module Aggregator
        # Test helpers for stream aligner
        module TestHelpers
            # write `sample` to `port` and waits until status reader `latest_time` equals
            # sample time
            def stream_aligner_write(task, port, sample, time_field: "timestamp", &block)
                reader = stream_aligner_status_reader(task)
                expect_execution do
                    syskit_write port, sample
                end.to do
                    have_one_new_sample(reader).matching do |t|
                        t[time_field] == sample[time_field]
                    end
                    instance_eval(&block) if block # let the caller add more predicates
                end
            end

            def stream_aligner_status_reader(task)
                @stream_aligner_status_reader[task] ||=
                    syskit_create_reader(task.transformer_stream_aligner_status_port,
                                         type: :buffer, size: 20)
            end

            # setup called in minitest's before block
            def setup
                @stream_aligner_status_reader = {}
                super
            end

            # teardown called in minitest's after block
            def teardown
                @stream_aligner_status_reader.each_value(&:disconnect)
                super
            end
        end
    end
end
