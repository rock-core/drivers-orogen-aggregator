# frozen-string-literal: true

# no-doc
module Syskit
    module Aggregator
        # Test helpers for stream aligner
        module TestHelpers
            # write `sample` to `port` and waits until status reader `latest_time` equals
            # sample time
            def stream_aligner_write(
                task, port, sample, sample_time_field: "timestamp", &block
            )
                reader = stream_aligner_status_reader(task)
                writer = syskit_create_writer port
                expect_execution { writer.write(sample) }
                    .to do
                        have_one_new_sample(reader).matching do |t|
                            t.latest_time == sample[sample_time_field]
                        end
                        # let the caller add more predicates
                        instance_eval(&block) if block
                    end
            end

            def stream_aligner_status_reader(task)
                property_name, port_name =
                    if task.properties.include?(:transformer_status_period)
                        # Transformer task
                        %I[transformer_status_period
                           transformer_stream_aligner_status]
                    else
                        # Pure stream aligner task
                        %I[stream_aligner_status_period stream_aligner_status]
                    end

                if task.property(property_name).read != 0
                    raise ArgumentError,
                          "The stream aligner task needs to have a zero " \
                          "status_period for the test helpers to work"
                end

                @stream_aligner_status_reader[task] ||=
                    syskit_create_reader(
                        task.find_port(port_name), type: :buffer, size: 20
                    )
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
