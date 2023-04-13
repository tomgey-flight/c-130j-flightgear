props.globals.initNode("/controls/switches/battery-master", 0, "DOUBLE");

var sys = props.globals.getNode("/sim/systems", 1);
var rule = sys.addChild("property-rule");
rule.setValue("name", "Battery");

debug.dump(rule);
