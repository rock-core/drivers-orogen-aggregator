module PortListenerPlugin
    class Extension
	attr_reader :in_loop_code
        attr_reader :port_listeners

	def initialize
	    @port_listeners = Hash.new()
	    @in_loop_code = Array.new()
	end
	
        def register_for_generation(task)
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
    end

    def self.add_to(task)
        if task.has_extension?("port_listener")
            return
        end
        task.register_extension "port_listener", Extension.new
    end
end

module StreamAlignerPlugin
    class Generator
	def generate_port_listener_code(task, config)
            port_listener_ext = task.extension("port_listener")

            agg_name = config.name
	    config.streams.each do |m| 
		index_name = m.port_name + "_idx"
		
		#push data in update hook
		port_listener_ext.add_port_listener(m.port_name) do |sample_name|
		    "
	#{agg_name}.push(#{index_name}, #{sample_name}.time, #{sample_name});"
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
	    task.add_base_member("aggregator", agg_name, "aggregator::StreamAligner")
	    task.add_base_member("lastStatusTime", "_lastStatusTime", "base::Time")

	    task.in_base_hook("configure", "
    #{agg_name}.clear();
    #{agg_name}.setTimeout( base::Time::fromSeconds( _aggregator_max_latency.value()) );
	    ")

	    config.streams.each do |m|     
		callback_name = m.port_name + "Callback"

		port_data_type = m.get_data_type(task)
	                             
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
    #{index_name} = #{agg_name}.registerStream< #{port_data_type}>(
	boost::bind( &TaskBase::#{callback_name}, this, _1, _2 ),
	#{buffer_size_factor}* ceil( #{config.max_latency}/#{m.port_name}Period),
	base::Time::fromSeconds( #{m.port_name}Period ) );
    _lastStatusTime = base::Time();")

		#deregister in cleanup hook
		task.in_base_hook('cleanup', "
    #{agg_name}.unregisterStream(#{index_name});")
		
	    end
	    
	    task.in_base_hook('update', "
    {
	const base::Time curTime(base::Time::now());
	if(curTime - _lastStatusTime > base::Time::fromSeconds(1))
	{
	    _lastStatusTime = curTime;
	    _#{agg_name}_status.write(#{agg_name}.getStatus());
	}
    }")

	    task.in_base_hook('stop', "
    #{agg_name}.clear();
    ")
	end
    end

    class Stream
	def initialize(name, period)
	    @port_name = name
	    @data_period = period
	end

	attr_reader :port_name
	attr_reader :data_period
	
	def get_data_type(task)
	    port = task.find_port(port_name)
	    if(!port)
		raise "Error trying to align nonexisting port " + port_name
	    end
	    
	    port.type.cxx_name	    
	end
    end
    
    class Extension
	attr_reader :name
	dsl_attribute :max_latency	
	attr_reader :streams
	
	def initialize()
	    @streams = Array.new()
            @name = "aggregator"
	end
	
	def align_port(name, default_period = 0)
	    streams << Stream.new(name, default_period)
	end	

        def update_spec(task)
	    task.project.import_types_from('aggregator')

	    Orocos::Spec.info("stream_aligner: adding property aggregator_max_latency")
	    task.property("aggregator_max_latency",   'double', max_latency).
			doc "Maximum time that should be waited for a delayed sample to arrive"
	    Orocos::Spec.info("stream_aligner: adding port #{name}_status")
	    task.output_port("#{name}_status", '/aggregator/StreamAlignerStatus')

	    #add output port for status information

	    streams.each do |m| 
		#add propertie for adjusting the period if not existing yet
		#this needs to be done now, as the properties must be 
		#present prior to the generation handler call
		property_name = "#{m.port_name}_period"
		if(!(task.find_property(property_name)))
		    task.property(property_name,   'double', m.data_period).
			doc "Time in s between #{m.port_name} readings"
		    Orocos::Spec.info("stream_aligner: adding property #{property_name}")
		end
            end
        end

        def register_for_generation(task)
            #register code generator to be called after parsing is done
            Generator.new.generate(task, self)
        end
    end
end


class Orocos::Spec::TaskContext
    def stream_aligner(&block)	
        PortListenerPlugin.add_to(self)

	config = StreamAlignerPlugin::Extension.new()
	config.instance_eval(&block)
	if !config.max_latency
	   raise ArgumentError, "no max_latency specified for the stream aligner" 
	end
    
        config.update_spec(self)
        register_extension("stream_aligner", config)
    end
end

