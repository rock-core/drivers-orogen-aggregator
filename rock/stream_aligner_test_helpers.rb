# frozen-string-literal: true

# no-doc
module Syskit
    module Aggregator
        # Test helpers for stream aligner
        module TestHelpers
            # Writes a sample to a stream aligned component and waits for its processing
            #
            # @param task
            # @param port The port where the sample must be written. This port must be
            #    an aligned port w.r.t. the stream aligner configuration.
            # @param sample The sample that must be written
            # @param [String] sample_time_field name of the field in the sample that
            #    contains the logical time, if it is not 'timestamp'
            # @param block if needed, pass additional `expect_execution` predicates within
            #    this block (statements that would be given in the `.to { }` block)
            # @return [Object] if additional predicates are given via a block, the value
            #    returned by these predicates. Otherwise, nothing
            #
            # @example basic usage
            #     # sample_time_field is necessary as RigidBodyState's timestamp field
            #     # is called `time`
            #     stream_aligner_write(
            #         task, task.input_port,
            #         Types.base.samples.RigidBodyState.new(
            #             time: Time.now,
            #             position: Types.base.Vector3d.new(0, 0, 0)
            #         ), sample_time_field: "time"
            #     )
            #
            # @example additional predicates can be specified in the to{} block
            #     input_sample =
            #         Types.base.samples.RigidBodyState.new(
            #             time: Time.now,
            #             position: Types.base.Vector3d.new(0, 0, 0)
            #         )
            #
            #     # the output value of stream_aligner_write is the output value of
            #     # the predicates setup by the block. Here, the matched sample.
            #     output_port_sample = stream_aligner_write(
            #         task, task.input_port, input_sample, sample_time_field: "time"
            #     ) do
            #         have_one_new_sample(task.output_port).matching do |t|
            #             t.position == expected_position
            #         end
            #     end
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
            # Returns a reader to access the status of a stream aligner
            #
            # The task may be using the stream aligner directly, or be based on
            # the transformer.
            #
            # @param task
            #
            # @return reader
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
            #
            # There's no need to call then anywhere inside your tests.
            def setup
                @stream_aligner_status_reader = {}
                super
            end

            # @api private
            #
            # Teardown called in minitest's after block by default.
            #
            # There's no need to call then anywhere inside your tests.
            def teardown
                @stream_aligner_status_reader.each_value(&:disconnect)
                super
            end
        end
    end
end
