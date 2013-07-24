#!/usr/bin/perl

# License
#   GPLv2 (http://www.gnu.org/licenses/gpl-2.0.txt)
# Authors
#   DENNI Tristan

use strict;
use Data::Dumper;
use JSYNC;
use Net::RabbitFoot;
use JSON::XS;

my $obj = JSYNC::load(<STDIN>);

my $rabbit_address = "127.0.0.1";
my $rabbit_port = 5672;
my $rabbit_user = "guest";
my $rabbit_pwd = "guest";
my $connector = "Munin - MyServer";

sortingOffice($obj, $rabbit_address, $rabbit_port, $rabbit_user, $rabbit_pwd, $connector);

sub sortingOffice {
  my ($object, $rabbit_address, $rabbit_port, $rabbit_user, $rabbit_pwd, $connector) = @_;
	my ($resource, $component, $metricObj, $metricData, $name, $type);

	my $connect = Net::RabbitFoot->new()->load_xml_spec()->connect(
		        host => $rabbit_address,
		        port => $rabbit_port,
		        user => $rabbit_user,
		        pass => $rabbit_pwd,
		        vhost => 'canopsis',
       		);
	my $channel = $connect->open_channel();			

	foreach my $plugin (@$object) {
		$resource =  ${$plugin}{resource};
		$component =  ${$plugin}{component};
		$metricObj =  ${$plugin}{metric};
		foreach my $metric (@$metricObj) {
			$name = ${$metric}{name};
			$type = ${$metric}{type};
			$metricData = ${$metric}{data};
			if (defined $metricData) {
				my %hash = %$metricData;
				foreach my $timestamp (keys %hash) {
					deliveryDriver($connector, $component, $resource, $timestamp, $name, $hash{$timestamp}, $type, $channel);
					}
				}				
			}
		}
	$connect->close();
}

sub deliveryDriver {
	my ($connector, $component, $resource, $timestamp, $name, $value, $type, $channel) = @_;

	my $unencoded = {
			"connector_name" => $connector,
			"event_type" => "log",
			"source_type" => "resource",
			"component" => $component,
			"resource" => $resource,
			"state" => 0,
			"state_type" => 1,
			"output" => "Refreshing Munin's Data ...",
			"timestamp" => $timestamp,
			"perf_data_array" => [{
						"metric" => $name,
						"unit" => "",
						"value" => $value,
						"type" => $type
						}]
			};
	
	my $encoded = JSON::XS->new->utf8->space_after->encode($unencoded);
	
	$channel->publish(
			exchange => 'canopsis.events',
			routing_key => "cli.".$connector_name.".log.resource".$component.".".$resource,
			body => $encoded,
			);
}
