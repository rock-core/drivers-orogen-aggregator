# frozen-string-literal: true

# no-doc
module Syskit
    module Aggregator
        # Test helpers for stream aligner
        module TestHelpers
            # write `sample` to `port` and waits until status reader `latest_time` equals
            # sample time
            def stream_aligner_write(
                task,
                port,
                sample,
                sample_time_field: "timestamp",
                port_time_field: "timestamp",
                max_latency: 0.1,
                &block
            )
                reader = stream_aligner_status_reader(task)
                writer = syskit_create_writer port
                expect_execution.timeout(15).poll do
                    writer.write(sample)
                end.to do
                    have_one_new_sample(reader).matching do |t|
                        (t[port_time_field] - sample[sample_time_field])
                            .abs <= max_latency
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
            def stream_aligner_reader_setup
                @stream_aligner_status_reader = {}
                super
            end

            # teardown called in minitest's after block
            def stream_aligner_reader_teardown
                @stream_aligner_status_reader.each_value(&:disconnect)
                super
            end
        end
    end
end
