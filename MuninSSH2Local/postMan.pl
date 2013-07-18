#!/usr/bin/perl

use strict;
#use warnings;
use JSYNC;

my $path = "/var/lib/munin/";
my $obj = buildRrdObj($path);

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

	my ($path) = @_;
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
				my $this = {"id", $metric{id}, "name", $metric{name}, "type", $metric{type}, "data", parseRrd($metric{path})};
				bless($this, $metric{id});
				push(@metricObj, $this);
				undef %metric;
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
       	                	my $this = {"id", $metric{id}, "name", $metric{name}, "type", $metric{type}, "path", $metric{path}};
                        	bless($this, $metric{id});
                        	push(@metricObj, $this);
                        	undef %metric;
                        	}
			($type) = $_ =~ /.*\.(graph_\w*)\s.*$/;
			if (emptyVal($type) eq "graph_title") {
				($resource) = $_ =~ /.*\.graph_title\s(.*)$/;
				}
			}
	        if ((defined $tmpPlugin && $tmpPlugin ne $plugin)) {
			my @tmpMetric = @metricObj; #nécessaire pour éviter la réinitialisation de "metric" sur l'objet
                	my $this = {"component", $tmpNode, "resource", $tmpPlugin, "metric", \@tmpMetric};
	                bless($this, $tmpDomain."-".$tmpNode."-".$tmpPlugin);
		        push(@obj, $this);
			undef @metricObj;
       		        }
		$tmpDomain = $domain;
		$tmpNode = $node;
		$tmpPlugin = $plugin;
		}
	unlink "/tmp/tmp_datafile2";
	return \@obj;
}

sub parseRrd {
	my ($path) = @_;

	my $timestamp;
	my $value;
	my $checking = 1;
	my %perf_data;

	if (-e "/tmp/tmp_rrd2.xml") { unlink "/tmp/tmp_rrd2.xml"; }
	`rrdtool dump $path >/tmp/tmp_rrd.xml2`;
	open(MYINPUTFILE, "/tmp/tmp_rrd.xml2");
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
		#génération du json string
		my ($value) = $line =~ /<v>(.*)<\/v>/;
        	if ($value ne "NaN") {
			$perf_data{$timestamp} = $value;			
			}
	};
	unlink "/tmp/tmp_rrd.xml2";
	return \%perf_data;
}
