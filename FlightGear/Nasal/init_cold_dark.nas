debug.dump("Initializing Cold and Dark...");
props.globals.initNode("/controls/switches/battery-master", 0, "DOUBLE");
setlistener("/controls/switches/battery-master", func(p) debug.dump(p.getValue() > 0.9 ? "on" : "off"));
