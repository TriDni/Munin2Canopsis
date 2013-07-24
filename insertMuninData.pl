#!/usr/bin/perl 

# License
#   GPLv2 (http://www.gnu.org/licenses/gpl-2.0.txt)
# Authors
#   DENNI Tristan

use strict;
use Net::RabbitFoot;
use JSON::XS;
use Term::Pager;
use Term::ReadKey;
use Data::Dumper;
use HTTP::Date;

my $syncPath = "/var/lib/munin/";
my $rabbit_address = "127.0.0.1";
my $rabbit_port = 5672;
my $rabbit_user = "guest";
my $rabbit_pwd = "guest";
my $connector = "Munin - IPRNagios";

system("clear");

print "\nWorking On Munin's Datafile, please wait few seconds ...\n\n";
$syncPath = addEndSlash($syncPath);
my $rrdObj = buildRrdObj($syncPath);
my (%component, %resource);
my ($columns, $rows) = GetTerminalSize();

my $i = 1;
print "Search for Component (Server) : ";
my $searchComponent = <>;
chomp($searchComponent);
print "\n";

foreach my $plugin (@$rrdObj) {
  if (${$plugin}{component} =~ /.*($searchComponent).*/) {
		foreach my $j (keys %component) {
			if ($component{$j} eq ${$plugin}{component}) {
				delete($component{$j});
				$i--;
				}
			}		
		$component{$i} = ${$plugin}{component};
		$i++;
		}
	}
my $printComponent = Term::Pager->new( rows => $rows, cols => $columns);
$printComponent->add_text("\n");
foreach my $key ( sort {$a<=>$b} keys %component) {
    $printComponent->add_text("[$key] $component{$key}\n");
	}
$printComponent->more();

if (not keys %component) { print "\nNo Result !\n"; exit; }

print "\nWhich Component's ID is interesting for you (only one) ? ";
my $selectedComponent = <>;
chomp($selectedComponent);
idControl($selectedComponent, %component);
print "\n";
$i = 1;

foreach my $plugin (@$rrdObj) {
	if (${$plugin}{component} eq $component{$selectedComponent}) {
		foreach my $j (keys %resource) {
            if ($resource{$j} eq ${$plugin}{resource}) {
                delete($resource{$j});
                $i--;
                }
            }       
        $resource{$i} = ${$plugin}{resource};
        $i++;
		}
	}

my $printResource = Term::Pager->new( rows => $rows, cols => $columns);
$printResource->add_text("\n");
foreach my $key ( sort {$a<=>$b} keys %resource) {
    $printResource->add_text("[$key] $resource{$key}\n");
    }
$printResource->more();

print "\nWhich Resource's ID is interesting for you (only one) ? ";
my $selectedResource = <>;
chomp($selectedResource);
idControl($selectedResource, %resource);

system("clear");
print "\nPlease set begin date (format : 'yyyy-MM-dd hh:mm:ss') [DEFAULT 'FIRST DATE EVER !'] : ";
my $beginDate = <>;
chomp($beginDate);
dateControl($beginDate);
my $beginTimestamp = str2time($beginDate);

print "\n\nPlease set end date (format : 'yyyy-MM-dd hh:mm:ss') [DEFAULT NOW] : "; 
my $endDate = <>;
chomp($endDate);
dateControl($endDate);
my $endTimestamp = str2time($endDate); 
if ($endTimestamp && $beginTimestamp &&($endTimestamp < $beginTimestamp)) { print "\nBegin date must be younger than End date !\n"; exit; }

my $connect = Net::RabbitFoot->new()->load_xml_spec()->connect(
        host => $rabbit_address,
        port => $rabbit_port,
        user => $rabbit_user,
        pass => $rabbit_pwd,
        vhost => 'canopsis',
        );
my $channel = $connect->open_channel();

system("clear");
print "\nConnected to RabbitMQ ...\n\nSending Data :\n".$component{$selectedComponent}." - ".$resource{$selectedResource}."\n";
if ($beginDate) { print "\nBegin Date : ".$beginDate." (".$beginTimestamp.")\n"; }
if ($endDate) { print "\nEnd Date : ".$endDate." (".$endTimestamp.")\n"; }

foreach my $plugin (@$rrdObj) {
	if (${$plugin}{resource} eq $resource{$selectedResource} and ${$plugin}{component} eq $component{$selectedComponent}) {
		my $resource = ${$plugin}{resource};
        my $component = ${$plugin}{component};
        my $metricObj = ${$plugin}{metric};
		my $i = 1;
        foreach my $metric (@$metricObj) {
            my $name = ${$metric}{name};
            my $path = ${$metric}{path};
            if (!-e $path) { next; }#on oublie si le fichier est inexistant
            my $stamp = 0;
            my $type = ${$metric}{type};
            my $connector_name = $connector;
            parseRrdAndSendIt($channel, $path, $connector_name, $component, $resource, $name, $type, $beginTimestamp, $endTimestamp);		
			print "\n[".$i."/".keys($metricObj)."] ".$name."\n";
			$i++;
			}
		print "\n";
		last;
		}	
	}
$connect->close();
print "\n\nJob done !\n\n";

sub dateControl { 
	my ($date) = @_;
	if (not $date =~ /^\d{4}-\d{2}-\d{2}\s\d{2}:\d{2}:\d{2}$/ and $date) { 
		print "\nPlease use expected datetime format !\n"; 
		exit; 
		}	
}

sub idControl {
	my ($id, %hash) = @_;
	if (not %hash or !defined $hash{$id}) {
		print "\nUnknown ID !\n\n";
		exit;
		}
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
			#génération du chemin du rrd pour la métrique
			if (defined $metric{type} && defined $domain && defined $node && defined $plugin && defined $metric{id}) {
				my $metricInstance = $metric{id};
				$metricInstance =~ s/\./-/;
				my $rrdPath = $path.$domain."/".$node."-".$plugin."-".$metricInstance.type2Ext($metric{type});
				$metric{path} = $rrdPath;
				}
			$tmpMetric = $instance;
			} 
		else { #plugin config
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
			my @tmpMetric = @metricObj; #nécessaire pour éviter la réinitialisation de "metric" sur l'objet
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
	my ($channel, $path, $connector_name, $component, $resource, $metric, $type, $beginTimestamp, $endTimestamp) = @_;
	my $laststamp = 0;

	my $output = "Refreshing Resource Perf Data";
	my $timestamp;
	my $perf_data_metric = $metric;
	my $perf_data_value;
	my $perf_data_type = $type;
	my $checking = 1;

	if (-e "/tmp/tmp_rrd.xml") { unlink "/tmp/tmp_rrd.xml"; }
	`rrdtool dump $path >/tmp/tmp_rrd.xml`;
	open(MYINPUTFILE, "/tmp/tmp_rrd.xml");
	while(<MYINPUTFILE>){
		my($line) = $_;
		chomp($line);
		
		#si on sort des valeurs AVERAGE (MIN ou MAX) on quitte le rrd
		if (($line =~ /^\s+<cf>MAX<\/cf>/)||($line =~ /^\s+<cf>MIN<\/cf>/)) { $checking = 0; }
		if ($line =~ /^\s+<cf>AVERAGE<\/cf>/) {	$checking = 1; }
		if ($checking == 0) { next; }
		#si la ligne n'est pas une ligne de données de perf on passe à la suivante
		if (not $line =~ /^\s*<!--\s\d{4}-\d{2}-\d{2}\s\d{2}:\d{2}:\d{2}.*/) { next; }
		($timestamp) = $line =~ /\/\s(\d{10})\s-->/;
		#récupération des données dans l'intervalle de temps
		if ($beginTimestamp) {
			if ($timestamp < $beginTimestamp) { next; }
			}
		if ($endTimestamp) {
			if ($timestamp > $endTimestamp) { next; }
			}
		#génération du json string
		my ($value) = $line =~ /<v>(.*)<\/v>/;
		$perf_data_value = $value;
        if ($perf_data_value ne "NaN") {
			my $hash = {
	 	                "connector_name" => $connector_name,
                        "event_type" => "log",
                        "source_type" => "resource",
                        "component" => $component,
                        "resource" => $resource,
                        "state" => 0,
                        "state_type" => 1,
                        "output" => $output,
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
	};
	unlink "/tmp/tmp_rrd.xml";
}
