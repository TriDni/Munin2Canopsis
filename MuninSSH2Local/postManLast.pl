#!/usr/bin/perl

# License
#   GPLv2 (http://www.gnu.org/licenses/gpl-2.0.txt)
# Authors
#   DENNI Tristan (http://triden.org)

use strict;
use JSYNC;
use Getopt::Long;

my ($path, $domain, $help);

GetOptions ('munin-path=s' => \$path, 'domain=s' => \$domain, 'help' => \$help);

if (defined $help or $ARGV[0] eq "help") { usage();}
if (!defined $path) { $path = "/var/lib/munin/"; } else { addEndSlash($path); }

my $obj = buildRrdObj($path, $domain);

my $json = JSYNC::dump($obj);#, {pretty => 1});
print $json;

sub addEndSlash {
  my ($string) = @_;
	if (not $string =~ /.*\/$/) { $string .= "/"; }
	return $string;
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

sub buildRrdObj {

	my ($path, $filterDomain) = @_;
	$path = addEndSlash($path);
	my $datafile = $path."datafile";
	my ($domain, $node, $plugin, $instance, $type, $value, $resource, $component);
	my (@obj, %metric, @metricObj);
	my ($tmpDomain, $tmpNode, $tmpPlugin, $tmpMetric, $tmpUnit);

	if (-e "/tmp/tmp_datafile2") { unlink "/tmp/tmp_datafile2"; }
	`sort -V $datafile > /tmp/tmp_datafile2`;

	open(DATAFILE, "/tmp/tmp_datafile2");
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
				my $data = parseRrd($metric{path});
				if (!defined ${$data}{NaN}) {	
					my $this = {"id", $metric{id}, "name", $metric{name}, "type", $metric{type}, "data", $data};
					bless($this, $metric{id});
					push(@metricObj, $this);
					undef %metric;
					}
				else { undef %metric; }
				}
			$metric{id} = $instance;
			if ($type eq "label") {
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
				my $data = parseRrd($metric{path});
				if (!defined ${$data}{NaN}) { 
	      	                	my $this = {"id", $metric{id}, "name", $metric{name}, "type", $metric{type}, "data", $data};
        	                	bless($this, $metric{id});
                	        	push(@metricObj, $this);
                        		undef %metric;
					}
				else { undef %metric; }
                        	}
			($type) = $_ =~ /.*\.(graph_\w*)\s.*$/;
			if (emptyVal($type) eq "graph_title") {
				($resource) = $_ =~ /.*\.graph_title\s(.*)$/;
				}
			}
	        if ((defined $tmpPlugin && $tmpPlugin ne $plugin)) {
			if ((defined $filterDomain && $tmpDomain && $filterDomain eq $tmpDomain) || !defined $filterDomain) {
				my @tmpMetric = @metricObj; #nécessaire pour éviter la réinitialisation de "metric" sur l'objet
                		my $this = {"component", $tmpNode, "resource", $tmpPlugin, "metric", \@tmpMetric};
	              		bless($this, $tmpDomain."-".$tmpNode."-".$tmpPlugin);
		        	push(@obj, $this);
				undef @metricObj;
	        		}
       		        }
		$tmpDomain = $domain;
		$tmpNode = $node;
		$tmpPlugin = $plugin;
		}
	unlink "/tmp/tmp_datafile2";
	return \@obj;
}

sub usage {

        print "\n\n == Options == ";
        print "\n\n--domain        munin-node to filter (like localdomain, folder in /var/lib/munin/)\n";
        print "--munin-path    root path of munin RRD (default : /var/lib/munin/)\n\n";
	print "--help or help     show this\n\n";

        exit;

}

sub parseRrd {
        my ($path) = @_;

        my %perf_data;
        my $last = `rrdtool info $path |grep last_ds`;
        my $timestamp = `rrdtool last $path`;
        chomp($last);
        chomp($timestamp);
        my ($value) = $last =~ /.*=\s+\"(.*)\"/;

        if ($value ne "NaN" && $value ne "U") { $perf_data{$timestamp} = $value; }
	else { $perf_data{NaN} = "NaN"; }
	return \%perf_data;
}

