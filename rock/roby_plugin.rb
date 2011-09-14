module Aggregator
    # Module that gets included in Orocos::RobyPlugin::TaskContext to add some
    # aggregator-related information
    module TaskExtension
        attribute(:aligned_ports_periods) { Hash.new }
        def configure
            super if defined? super
            aligned_ports_periods.each do |port_name, period|
                property("#{port_name}_period").set(period)
            end
        end

        module ClassExtension
            def stream_aligner; orogen_spec.stream_aligner end
        end
    end

    # Module included in Orocos::RobyPlugin::Graphviz to add new annotation
    # possibilities
    module GraphvizExtension
        def add_stream_period_annotations
            plan.find_local_tasks(Orocos::RobyPlugin::TaskContext).each do |task|
                if agg = task.model.stream_aligner
                    ann = agg.each_aligned_port.map do |p|
                        if period = task.aligned_ports_periods[p.name]
                            "#{p.name}: #{period}"
                        else
                            "#{p.name}: unknown"
                        end
                    end
                    add_task_annotation(task, "Stream Aligner", ann)
                end
            end
        end
    end

    Orocos::RobyPlugin::Engine.register_deployment_postprocessing do |engine, tasks|
        dynamics = engine.port_dynamics
        engine.plan.find_local_tasks(Orocos::RobyPlugin::TaskContext).each do |task|
            agg = task.model.stream_aligner
            if !agg
                Orocos::RobyPlugin::Engine.debug "stream_aligner: #{task} has no stream aligner"
                next
            end

            dyn = dynamics[task]
            if !dyn
                Orocos::RobyPlugin::Engine.debug "stream_aligner: no port dynamics for #{task}, ignoring"
                next
            end

            agg.each_aligned_port do |p|
                if !(port_dyn = dyn[p.name])
                    port_dyn = task.update_input_port_dynamics(p.name)
                end

                if port_dyn && (min_period = port_dyn.minimal_period)
                    task.aligned_ports_periods[p.name] = min_period * 0.8
                else
                    Orocos::RobyPlugin::Engine.warn "cannot compute input period for aligned port #{task.name}:#{p.name}, setting period to 0"
                    task.aligned_ports_periods[p.name] = 0
                end
            end
        end
    end
end

Orocos::RobyPlugin::TaskContext.include Aggregator::TaskExtension
Orocos::RobyPlugin::Graphviz.include Aggregator::GraphvizExtension
Roby.app.filter_out_patterns.push(/^#{Regexp.quote(__FILE__)}/)
