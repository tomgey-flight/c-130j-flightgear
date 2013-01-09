# ==============================================================================
# Crew alerting system
# ==============================================================================
var CAS =
{
  #
  #
  # @param dt Update interval (sec)
	new: func(node, file, lines, dt = 0.5)
	{
		var m = {
		  parents: [CAS],
		  _types: ['caution', 'warning', 'status'],
		  _colors: [[1,0,0], [1,1,0], [1,1,1]],
		  _msg: {},
		  _dt: dt
		};
		m.lines = lines;
		m.node = aircraft.makeNode(node);
		m.file = file;
		m.reload();
		return m;
	},
	reload: func(file = nil)
	{
	  # clear old messages
	  foreach(var type; me._types)
		  me._msg[type] = [];

	  # and load new ones
		me.file = file == nil ? me.file : file;
    var messages = io.read_properties(me.file).getChildren("message");
    
    foreach(var message; messages)
		{
			var type = message.getNode("type", 1).getValue();
			if( me._msg[type] == nil )
			{
			  debug.warn("Unknown message type: " ~ type);
			  continue;
			}
			
			append
			(
			  me._msg[type],
			  {
				  text: message.getNode("text", 1).getValue(),
				  condition: message.getNode("condition", 1),
				  active: 0,
				  line: -1  # line where the message is currently displayed
			  }
			);
		}
	},
	check: func
	{
	  var cur_line = 0;
		for(var i = 0; i < size(me._types); i += 1)
		{
		  var type = me._types[i];
		  var color = me._colors[i];

			foreach(var msg; me._msg[type])
			{
				if( props.condition(msg.condition) )
				{
					if( msg.line != cur_line )
					{
					  msg.line = cur_line;
					  
					  if( !msg.active )
					  {
					    print(msg.text);
					    msg.active = 1 + 10;
					    setprop("sim/sound/cas-msg-status", 0);
					    setprop("sim/sound/cas-msg-status", 1);
					  }
					  
					  if( msg.active > 1 )
					  {
					    me.lines[cur_line].setColorFill(color)
					                      .setColor(0,0,0)
					                      .setDrawMode
					                      (
					                        canvas.Text.TEXT
					                      + canvas.Text.FILLEDBOUNDINGBOX
					                      )
					                      .setPadding(2);
					  }
					  else
					  {
					    me.lines[cur_line].setColor(color)
					                      .setDrawMode(canvas.Text.TEXT);
					  }
					  
					  me.lines[cur_line].setText(msg.text)
					                    .show()
                              .update();
					}
					
					if( msg.active > 1 )
					{
					  msg.active -= me._dt;
					  
					  if( msg.active <= 1 )
					  {
					    msg.active = 1;
					    
					    me.lines[cur_line].setColor(color)
					                      .setDrawMode(canvas.Text.TEXT)
					                      .update();
					  }
					}

					cur_line += 1;
			  }
			  else
			  {
			    if( msg.active )
			    {
			      print("!" ~ msg.text);
			      msg.active = 0;
			      msg.line = -1;
			    }
			  }

			  if( cur_line == size(me.lines) )
			  {
			    # TODO  handle overflow
			    print("CAS overflow");
			    break;
			  }
			}
			
		  if( cur_line == size(me.lines) )
		    break;
		}
		
    for(; cur_line < size(me.lines); cur_line += 1)
      me.lines[cur_line].hide();
	},
	update: func
	{
#		debug.benchmark("check", func me.check(), 10);
    me.check();
		settimer(func me.update(), me._dt);
	}
};

# ==============================================================================
# Head down display
# ==============================================================================

var HDD = {
  canvas_settings: {
    "name": "HDD",
    "size": [768, 1024],
    "view": [768, 1024],
    "mipmapping": 1
  },
  new: func(placement)
  {
    debug.dump("Initializing HDD...");
    
    var m = {
      parents: [HDD],
      canvas: canvas.new(HDD.canvas_settings),
      listener: [],
      listener_poll: [],
      init: 0
    };
    
    var font_mapper = func(family, weight)
    {
      if( family == "Ubuntu Mono" and weight == "bold" )
        return "UbuntuMono-B.ttf";
    };

    m.canvas.addPlacement(placement);
    m.canvas.setColorBackground(0.02, 0.04, 0.02);

    m.root = m.canvas.createGroup();
    canvas.parsesvg
    (
      m.root,
      getprop("/sim/aircraft-dir") ~ "/Instruments/EICAS.svg",
      {'font-mapper': font_mapper}
    );
    var acaws = m.root.getElementById("ACAWS_10");
    acaws.setText("THE NEW API IS COOL!");
    acaws.setColor(1,0,0);

    m.eng = setsize([], 4);
    for(var i = 0; i < 4; i += 1)
    {
      var eng = m.root.getElementById("eng" ~ (i + 1));

      m.eng[i] = {
        box: eng.getElementById("box"),
        msg: eng.getElementById("msg")
      };
      m.eng[i].box.hide();
      m.eng[i].msg.setText("");

      m.connect
      (
        "/fdm/jsbsim/propulsion/engine[" ~ i ~ "]/power-hp",
        func(d, val)
        {
          var hp_rad = val * (248.3/4600) * math.pi/180;
          d.arc._node.getNode("cmd[1]").setIntValue
          (
            hp_rad < math.pi ? canvas.Path.VG_SCWARC_TO_REL
                             : canvas.Path.VG_LCWARC_TO_REL
          );
          d.arc._node.getNode("coord[5]").setDoubleValue(49 * math.sin(hp_rad));
          d.arc._node.getNode("coord[6]").setDoubleValue(49 * (1 - math.cos(hp_rad)));
          d.dial.setRotation(hp_rad);
          d.text.setText(sprintf("%.0f", val));
        },
        {
          arc: eng.getElementById("arc_hp"),
          dial: eng.getElementById("dial_hp").updateCenter(),
          text: eng.getElementById("readout_hp")
        }
      );
      m.connect
      (
        "/fdm/jsbsim/propulsion/engine[" ~ i ~ "]/itt-c",
        func(d, val)
        {
          d.dial.setRotation(val * (248.3/960) * math.pi/180);
          d.text.setText(sprintf("%.0f", val));
        },
        {
          dial: eng.getElementById("dial_mgt").updateCenter(),
          text: eng.getElementById("readout_mgt")
        }
      );
      m.connect
      (
        "/engines/engine[" ~ i ~ "]/n1",
        func(d, val)
        {
          d.dial.setRotation(val * (248.3/103) * math.pi/180);
          d.text.setText(sprintf("%.0f", val));
        },
        {
          dial: eng.getElementById("dial_ng").updateCenter(),
          text: eng.getElementById("readout_ng")
        }
      );
      m.connect
      (
        "/engines/engine[" ~ i ~ "]/thruster/rpm",
        func(ob, val) ob.setText(sprintf("%.0f", val * 100.0 / 1057)),
        eng.getElementById("NP")
      );      
      m.connect
      (
        "/engines/engine[" ~ i ~ "]/fuel-flow_pph",
        func(ob, val) ob.setText(sprintf("%.0f", val)),
        eng.getElementById("FF")
      );
      m.connect
      (
        "/engines/engine[" ~ i ~ "]/oil-pressure-psi",
        func(d, val) d.setText(sprintf("%.1f", val)),
        eng.getElementById("E_PSI")
      );
      m.connect
      (      
        "/engines/engine[" ~ i ~ "]/oil-temperature-degf",
        func(d, val) d.setText(sprintf("%.0f", (val - 32) * 5.0/9)),
        eng.getElementById("TEMP")
      );
    }

    m.acaws = setsize([], 15);
    for(var i = 0; i <= 14; i += 1)
      m.acaws[i] = m.root.getElementById("ACAWS_" ~ i);

    m.input = {
      pitch:    "/orientation/pitch-deg",
      roll:     "/orientation/roll-deg",
      hdg:      "/orientation/heading-deg",
      speed_n:  "velocities/speed-north-fps",
      speed_e:  "velocities/speed-east-fps",
      speed_d:  "velocities/speed-down-fps",
      alpha:    "/orientation/alpha-deg",
      beta:     "/orientation/side-slip-deg",
      ias:      "/velocities/airspeed-kt",
      gs:       "/velocities/groundspeed-kt",
      vs:       "/velocities/vertical-speed-fps",
      rad_alt:  "/instrumentation/radar-altimeter/radar-altitude-ft",
      wow_nlg:  "/gear/gear[4]/wow"
    };
    
    foreach(var name; keys(m.input))
      m.input[name] = props.globals.getNode(m.input[name], 1);
    
    return m;
  },
  connect: func(prop, cb, data = nil)
  {
    var node = props.globals.getNode(prop);
    if( 1 or node.getAttribute("tied") )
    {
      print("New tied connection for " ~ prop);
      append(me.listener_poll, [
        node,
        data,
        cb,
        node.getValue()
      ]);
    }
    else
    {
      print("New listener connection for " ~ prop);
      append(me.listener, [
        prop,
        data,
        cb,
        setlistener(prop, func(p) cb(data, p.getValue()), 1, 0)
      ]);
    }
  },
  update: func()
  {
    if( me.init < 3 )
    {
      if( (me.init += 1) == 3 )
      {
        foreach(var lp; me.listener)
        {
          # lp = [prop, data, callback, last_value]
          lp[2](lp[1], getprop(lp[0]));
        }
      }
    }
    foreach(var lp; me.listener_poll)
    {
      # lp = [node, data, callback, last_value]
      var val = lp[0].getValue();
      if( lp[3] != val )
      {
        lp[2](lp[1], val);
        lp[3] = val;
      }
    }
    
#    if( getprop("/sim/fail") )
#    {
#      me.acaws[msg_index].setText("NAC 1 OVERHEAT");
#      me.acaws[msg_index].setColor(1,0,0);
#      msg_index += 1;
#
#      if( getprop("/engines/engine[0]/oil-pressure-psi") < 20 )
#      {
#        me.acaws[msg_index].setText("ENG 1 OIL PRESS LOW");
#        me.acaws[msg_index].setColor(1,1,0);
#        msg_index += 1;
#      }
#
#      setprop("/controls/engines/engine[0]/cutoff", 1);
#      me.eng[0].msg.setText("FAIL");
#    }

    settimer(func me.update(), 0.1);
  }
};

var init_hdd = setlistener("/sim/signals/fdm-initialized", func() {
  removelistener(init_hdd); # only call once
  var hdd1 = HDD.new({parent: "HDD 1", node: "PFD-Screen"});
  hdd1.update();
  
  var acaws = CAS.new("instrumentation/eicas-messages/page[0]", getprop("/sim/aircraft-dir") ~ "/Systems/acaws.xml", hdd1.acaws);
  acaws.update();
});
