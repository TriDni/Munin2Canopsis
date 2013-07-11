#!/usr/bin/perl 

use strict;
use warnings;
use Net::RabbitFoot;
use JSON::XS;

my $syncPath = "/var/lib/munin/";
my $rabbit_address = "127.0.0.1";
my $rabbit_port = 5672;
my $rabbit_user = "guest";
my $rabbit_pwd = "guest";
my $connector = "Munin - MyServer";

scanRep($syncPath, $rabbit_address, $rabbit_port, $rabbit_user, $rabbit_pwd, $connector);

sub scanRep {
  my ($syncedPath, $rabbit_address, $rabbit_port, $rabbit_user, $rabbit_pwd, $connector) = @_;
	my %hash;
	$syncedPath = addEndSlash($syncedPath);
	
    my $connect = Net::RabbitFoot->new()->load_xml_spec()->connect(
        host => $rabbit_address,
        port => $rabbit_port,
        user => $rabbit_user,
        pass => $rabbit_pwd,
        vhost => 'canopsis',
        );
    my $channel = $connect->open_channel();
 
		my $rrdObj = buildRrdObj($syncedPath);
		foreach my $plugin (@$rrdObj) {
			my $resource = ${$plugin}{resource};
			my $component = ${$plugin}{component};
			my $unit = ${$plugin}{unit};
			my $metricObj = ${$plugin}{metric};
			foreach my $metric (@$metricObj) {
				my $max = ${$metric}{max};
				my $min = ${$metric}{min};
				my $name = ${$metric}{name};
				my $path = ${$metric}{path};
				if (!-e $path) { next; }#next if rrd path is not set
				my $stamp = 0;
				my $type = ${$metric}{type};
				my $connector_name = $connector;
				parseRrdAndSendIt($channel, $path, $connector_name, $component, $resource, $name, $unit, $type, $max, $min, $stamp);	
				}
		}
	$connect->close();
}

sub addEndSlash {
	my ($string) = @_;
	if (not $string =~ /.*\/$/) { $string .= "/"; }
	return $string;
}

sub buildRrdObj {

	my ($path) = @_;
	$path = addEndSlash($path);
	my $datafile = $path."datafile";
	my ($domain, $node, $plugin, $instance, $type, $value, $unit, $resource, $component);
	my (@obj, %metric, @metricObj);
	my ($tmpDomain, $tmpNode, $tmpPlugin, $tmpMetric, $tmpUnit);

	`sort -V $datafile > /tmp/tmp_datafile`;

	open(DATAFILE, "/tmp/tmp_datafile");
	while(<DATAFILE>){
	if ($_ =~ /^version.*/) { next; }
		($plugin) = $_ =~ /^.*;.*:([\w*|\-*]*)\.[\w*|\-*]*.*$/;
		($domain) = $_ =~ /^(.*);.*/;
		($node) = $_ =~ /^.*;(.*):.*/;
		if ((not $_ =~ /.*\.graph_.*\s+.*$/) && (not $_ =~ /.*\.host_name\s+.*$/))  {
			($instance) = $_ =~ /^.*;.*:[\w*|\-*]*\.([\w*|\-*|\.*]*)\.[\w*|\-*]*\s+.*$/;
			($type) = $_ =~ /^.*;.*:[\w|\.|\-]*\.([\w*|\-*]*)\s+.*$/;
			($value) = $_ =~ /\s+(.*)$/;
			if ((%metric && (defined $tmpMetric && $tmpMetric ne $instance) || (defined $tmpPlugin && $tmpPlugin ne $plugin)) && (defined $metric{id} && defined $metric{name} && defined $metric{type} && defined $metric{path})) {
				my $this = {"id", $metric{id}, "name", $metric{name}, "type", $metric{type}, "min", $metric{min}, "max", $metric{max}, "path", $metric{path}};
				bless($this, $metric{id});
				push(@metricObj, $this);
				undef %metric;
				}
			$metric{id} = $instance;
			if ($type eq "min") {
				$metric{min} = emptyVal($value);
				}
			elsif ($type eq "max") {
				$metric{max} = emptyVal($value);
				}
			elsif ($type eq "label") {
				$metric{name} = emptyVal($value);
				}
			elsif ($type eq "type") {
				$metric{type} = emptyVal($value);
				}
			#find absolute path of rrd file
			if (defined $metric{type} && defined $domain && defined $node && defined $plugin && defined $metric{id}) {
				my $metricInstance = $metric{id};
				$metricInstance =~ s/\./-/;
				my $rrdPath = $path.$domain."/".$node."-".$plugin."-".$metricInstance.type2Ext($metric{type});
				$metric{path} = $rrdPath;
				}
			$tmpMetric = $instance;
			} 
		else { #get plugin config
			if (defined $tmpPlugin && $tmpPlugin ne $plugin && %metric && (defined $metric{id} && defined $metric{name} && defined $metric{type} && defined $metric{path})) {
       	                	my $this = {"id", $metric{id}, "name", $metric{name}, "type", $metric{type}, "min", $metric{min}, "max", $metric{max}, "path", $metric{path}};
                        	bless($this, $metric{id});
                        	push(@metricObj, $this);
                        	undef %metric;
                        	}
			($type) = $_ =~ /.*\.(graph_\w*)\s.*$/;
			if (emptyVal($type) eq "graph_title") {
				($resource) = $_ =~ /.*\.graph_title\s(.*)$/;
				}
			elsif (emptyVal($type) eq "graph_vlabel") {
				($unit) = $_ =~ /.*\.graph_vlabel\s(.*)$/;
				}
			}
	        if ((defined $tmpPlugin && $tmpPlugin ne $plugin)) {
			my @tmpMetric = @metricObj; #needed to have another ref for this value (and not erase it)
                	my $this = {"component", $tmpNode, "resource", $tmpPlugin, "unit", emptyVal($unit), "metric", \@tmpMetric};
	                bless($this, $tmpDomain."-".$tmpNode."-".$tmpPlugin);
		        push(@obj, $this);
			undef @metricObj;
       		        }
		$tmpDomain = $domain;
		$tmpNode = $node;
		$tmpPlugin = $plugin;
		$tmpUnit = $unit;
		}
	unlink "/tmp/tmp_datafile";
	return \@obj;
}

sub emptyVal {
	my ($value) = @_;
	if (!defined $value) {
		$value = "";
		}
	elsif ($value =~ /^\s*U\s*$/) {
		$value = "";
		}
	elsif ($value =~ /^\s*.*/) {
		$value =~ s/^\s+//;
		}
	elsif ($value =~ /.*\s*$/) {
		$value =~ s/\s+$//;
		}
	return $value;	
}

sub type2Ext {
	my ($value) = @_;
	my $return;
	if ($value =~ /GAUGE/) {
		$return = "-g.rrd";
		}
	elsif ($value =~ /DERIVE/) {
		$return = "-d.rrd";
		}
	elsif ($value =~ /COUNTER/) {
		$return = "-c.rrd";
		}
	elsif ($value =~ /ABSOLUTE/) {
		$return = "-a.rrd";
		}
	return $return;
}


sub parseRrdAndSendIt {
	my ($channel, $path, $connector_name, $component, $resource, $metric, $unit, $type, $max, $min, $tmpstamp) = @_;

	my $entity, my $inputFile;
	my $sourceFile = $path;

	my $output = "Refreshing Resource Perf Data";
	my $timestamp;
	my $perf_data_metric = $metric;
	my $perf_data_unit = $unit;
	my $perf_data_value;
	my $perf_data_type = $type;

	my $last = `rrdtool info $sourceFile |grep last_ds`;
	$timestamp = `rrdtool last $sourceFile`;
	
	chomp($last);
	chomp($timestamp);
	($perf_data_value) = $last =~ /.*=\s+\"(.*)\"/;
	if ($perf_data_value ne "NaN" && $perf_data_value ne "U") {	
		my $hash = {
			       "connector_name" => $connector_name,
		           "event_type" => "log",
		           "source_type" => "resource",
		           "component" => $component,
		           "resource" => $resource,
		           "state" => 0,
		           "state_type" => 1,
		           "output" => $perf_data_unit,
		           "timestamp" => $timestamp,
		           "perf_data_array" => [{
						     "metric" => $perf_data_metric,
			                             "unit" => "",
			                             "value" => $perf_data_value,
			                             "type" => $perf_data_type
			                             }]
		           };
		my $json = JSON::XS->new->utf8->space_after->encode($hash);
		$channel->publish(
				exchange => 'canopsis.events',
				routing_key => "cli.".$connector_name.".log.resource".$component.".".$resource,
				body => $json,
				);
		}
}
