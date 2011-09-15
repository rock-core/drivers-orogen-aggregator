# General underlying support for code generation where data gets pulled from the
# ports
#
# To pull data from ports, one needs to have a single loop where the data get
# read and then dispatched to all registered listeners. This plugin provides the
# underlying capability of registering the listeners, and then generate the code
# to push data to all of them
module PortListenerPlugin
    # The extension that gets registered on TaskContext
    class Extension
	attr_reader :in_loop_code
        attr_reader :port_listeners

	def initialize
	    @port_listeners = Hash.new()
	    @in_loop_code = Array.new()
	end
	
        def register_for_generation(task)
            # Use a block so that the code generation gets delayed. This makes
            # sure that all listeners are registered properly before we generate
            # the code
	    task.in_base_hook("update") do
	    code = "
    bool keepGoing = true;
    
    while(keepGoing)
    {
	keepGoing = false;
	"        
	    port_listeners.each do |port_name, gens|
	    
		port = task.find_port(port_name)
		if(!port)
		    raise "Internal error trying to listen to nonexisting port " + port_name 
		end
		
		code += "
	#{port.type.cxx_name} #{port_name}Sample;
	if(_#{port_name}.read(#{port_name}Sample, false) == RTT::NewData )
	{"
	    gens.each{|gen| code += gen.call("#{port_name}Sample")}
	    code += "
	    keepGoing = true;
	}"                   
	    end
	    
	    in_loop_code.each do |block|
		code += block
	    end
	    
	    code +="
    }"
            end
	end	
    
        def add_port_listener(name, &generator_method)
            Orocos::Generation.info "added port listener for port #{name}"
            
            if(!port_listeners[name])
                port_listeners[name] = Array.new
            end
            
            port_listeners[name] << generator_method
        end
        
        def add_code_after_port_read(code)
            in_loop_code << code
        end

        def pretty_print(pp)
        end
    end

    def self.add_to(task)
        if task.has_extension?("port_listener")
            return
        end
        task.register_extension "port_listener", Extension.new
    end
end

# Support for the usage of the stream aligner in oroGen 
module StreamAlignerPlugin
    # Class that takes care of the C++ code generation from a stream aligner
    # specification
    class Generator
	def generate_port_listener_code(task, config)
            port_listener_ext = task.extension("port_listener")

            agg_name = config.name
	    config.streams.each do |m| 
		index_name = m.port_name + "_idx"
		
		#push data in update hook
		port_listener_ext.add_port_listener(m.port_name) do |sample_name|
		    "
	_#{agg_name}.push(#{index_name}, #{sample_name}.time, #{sample_name});"
		end
	    end
	    
	    port_listener_ext.add_code_after_port_read("
	while(aggregator.step()) 
	{
	    ;
	}")
	end
	
	def generate(task, config)
            agg_name = config.name
            generate_port_listener_code(task, config)

	    task.add_base_header_code("#include<aggregator/StreamAligner.hpp>", true)
	    task.add_base_member("aggregator", "_#{agg_name}", "aggregator::StreamAligner")
	    task.add_base_member("lastStatusTime", "_lastStatusTime", "base::Time")

	    task.in_base_hook("configure", "
    _#{agg_name}.clear();
    _#{agg_name}.setTimeout( base::Time::fromSeconds( _aggregator_max_latency.value()) );
	    ")

	    config.streams.each do |m|     
		callback_name = m.port_name + "Callback"

		port_data_type = type_cxxname(m, task)
	                             
		#add callbacks
		task.add_user_method("void", callback_name, "const base::Time &ts, const #{port_data_type} &#{m.port_name}_sample").
		body("    throw std::runtime_error(\"Aggregator callback for #{m.port_name} not implemented\");")

		index_name = m.port_name + "_idx"

		buffer_size_factor = 2.0

		#add variable for index
		task.add_base_member("aggregator", index_name, "int")

		#register callbacks at aggregator
		task.in_base_hook("configure", "
    const double #{m.port_name}Period = _#{m.port_name}_period.value();
    #{index_name} = _#{agg_name}.registerStream< #{port_data_type}>(
	boost::bind( &TaskBase::#{callback_name}, this, _1, _2 ),
	#{buffer_size_factor}* ceil( #{config.max_latency}/#{m.port_name}Period),
	base::Time::fromSeconds( #{m.port_name}Period ) );
    _lastStatusTime = base::Time();")

		#deregister in cleanup hook
		task.in_base_hook('cleanup', "
    _#{agg_name}.unregisterStream(#{index_name});")
		
	    end
	    
	    task.in_base_hook('update', "
    {
	const base::Time curTime(base::Time::now());
	if(curTime - _lastStatusTime > base::Time::fromSeconds(1))
	{
	    _lastStatusTime = curTime;
	    _#{agg_name}_status.write(_#{agg_name}.getStatus());
	}
    }")

	    task.in_base_hook('stop', "
    _#{agg_name}.clear();
    ")
	end
	
	def type_cxxname(stream, task)
	    port = task.find_input_port(stream.port_name)
	    if(!port)
		raise "Error trying to align nonexisting port " + port_name
	    end
	    
	    port.type.cxx_name
	end
    end

    # Definition of a single stream
    class Stream
        # Adds a new stream. +name+ is the task's port name and +period+ the
        # default period
        #
        # It is strongly advised to keep the period to zero
	def initialize(name, period = 0)
	    @port_name = name
	    @data_period = period
	end

        # The task's port name
	attr_reader :port_name
        # The period of the incoming data. It is strongly advised to keep it to
        # zero in stream aligner specifications
	attr_reader :data_period
    end
    
    # Extension to the task model to represent the stream aligner setup
    class Extension
        # The stream aligner name. Always "aggregator" for now
	attr_reader :name

        # The task model on which this stream aligner is defined
        attr_reader :task_model

        ##
        # :method: max_latency
        # :call-seq:
        #   max_latency => value
        #   max_latency new_value => new_value
        #
        # Gets or sets the stream aligner's default maximum latency. It can also
        # be set at runtime using the aggregator_max_latency property
	dsl_attribute :max_latency	

        # The defined streams, as an array of Stream objects
	attr_reader :streams
	
	def initialize(task_model)
            @task_model = task_model
	    @streams = Array.new()
            @name = "stream_aligner"
	end

        # Enumerates the task ports that are aligned on this stream aligner
        def each_aligned_port(&block)
            streams.map { |s| task_model.find_input_port(s.port_name) }.each(&block)
        end
	
        # Declares that the stream aligner should be configured to pull data
        # from the input port +name+ with a default period of +default_period+
        #
        # Periods are highly system-specific. It is very stronly advised to keep
        # it to the default value of zero.
	def align_port(name, default_period = 0)
	    streams << Stream.new(name, default_period)
	end	

        # Adds to the task the interface objects for the benefit of the stream aligner
        def update_spec
            # Don't add the base interface elements if they already have been
            # added
            if !task_model.has_property?("aggregator_max_latency")
                task_model.project.import_types_from('aggregator')

                Orocos::Spec.info("stream_aligner: adding property aggregator_max_latency")
                task_model.property("aggregator_max_latency",   'double', max_latency).
                            doc "Maximum time that should be waited for a delayed sample to arrive"
                Orocos::Spec.info("stream_aligner: adding port #{name}_status")
                task_model.output_port("#{name}_status", '/aggregator/StreamAlignerStatus')
            end

	    streams.each do |m| 
		property_name = "#{m.port_name}_period"
		if !task_model.find_property(property_name)
		    task_model.property(property_name,   'double', m.data_period).
			doc "Time in s between #{m.port_name} readings"
		    Orocos::Spec.info("stream_aligner: adding property #{property_name}")
		end
            end
        end

        def register_for_generation(task)
            #register code generator to be called after parsing is done
            Generator.new.generate(task_model, self)
        end
    end
end


class Orocos::Spec::TaskContext
    # Adds a stream aligner to this task
    #
    # See http://rock-robotics.org/documentation/data_processing/index.html for
    # a general introduction
    #
    # The new stream aligner object is an instance of
    # StreamAlignerPlugin::Extension and can be retrieved with
    #
    #   task_model.stream_aligner
    #
    # Or, more generically,
    #
    #   task_model.extension("stream_aligner")
    #
    def stream_aligner(&block)	
        if !block_given?
            return find_extension("stream_aligner")
        end

        if !(config = find_extension("stream_aligner"))
            config = StreamAlignerPlugin::Extension.new(self)
            PortListenerPlugin.add_to(self)
        end

	config.instance_eval(&block)
	if !config.max_latency
	   raise ArgumentError, "no max_latency specified for the stream aligner" 
	end
    
        config.update_spec
        register_extension("stream_aligner", config)
    end
end

