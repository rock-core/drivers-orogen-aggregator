# frozen-string-literal: true

# no-doc
module Syskit
    module Aggregator
        # Test helpers for stream aligner
        #
        # These create a synchronization by using the `transformer_stream_aligner_port`
        # for transformer tasks or `stream_aligner_status_port` for pure stream aligner
        # tasks by checking the time of the processed samples until one matches the
        # written sample time or the timeout is reached.
        module TestHelpers
            # @api public
            #
            # Writes a sample to the port and wait until a status reader matching
            # `latest_time` and `sample_time_field` is found.
            # In addition, let's the caller call more predicates for the function
            # expect execution.
            #
            # @param [task]
            # @param [port] The port where the sample must be written
            # @param [sample] The sample that must be written
            # @param [sample_time_field] Parameter name as a string for
            #                            the time on the sample
            # @param [&block] Extra predicates needed for the test
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
                        # Allow the caller to call more predicates
                        instance_eval(&block) if block
                    end
            end

            # @api private
            #
            # Creates a reader with a buffer of size 20 to the task
            # and defines the correct port name and property name for
            # a transformer task or a pure stream aligner task.
            # Also, verifies if the Transformer_status_period is 0.
            # This is needed since the sample time must be equal to
            # reader latest time.
            # Finally, these readers are cached and disconnected on teardown.
            #
            # @param [task]
            #
            # return [Reader]
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

            # @api private
            #
            # Setup called in minitest's before block by default.
            # There's no need to call then anywhere inside your tests.
            def setup
                @stream_aligner_status_reader = {}
                super
            end

            # @api private
            #
            # Teardown called in minitest's after block by default.
            # There's no need to call then anywhere inside your tests.
            def teardown
                @stream_aligner_status_reader.each_value(&:disconnect)
                super
            end
        end
    end
end
