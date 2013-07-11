Munin2Canopsis
==============

This script is a connector for Canopsis. It allows to send in real time Munin's datas to Canopsis.

##Requirements


    sudo apt-get install make libclass-data-inheritable-perl libtest-deep-perl libmoosex-app-cmd-perl libcoro-perl libjson-xs-perl libxml-libxml-perl libconfig-any-perl libmoosex-attributehelpers-perl libmoosex-configfromfile-perl libtest-exception-perl libfile-sharedir-perl libreadonly-xs-perl libuuid-tiny-perl
    sudo cpan -i Net::RabbitFoot
    sudo cpan -i JSON::XS


##Installation


Edit top of munin2canopsis.pl script : change with your RabbitMQ's informations and your /var/lib/munin/ path, if it doesn't match with default settings.

You can now check if your settings are correct. Run munin2Canopsis.pl and check in your Canopsis Web UI if datas are here.

Then, you have to automate this script. I choose to had it in a Crontab to execute it every 5 minutes :

    */5 * * * *     root if [ -x /home/trid/script/munin2Canopsis.pl ]; then perl /home/trid/script/munin2Canopsis.pl; fi

##Warning

Take care to have enough space for MongoDB, and to not have more than 15000 RRDs to send to Canopsis. Indeed, RabbitMQ could queue AMQP messages if you have too much of these.
To verify your server capacity you can time the script and make sure that it takes less than 4-5 min to execute (munin-update time period).

    time ./munin2Canopsis.pl

Actually, it doesn't send any perdata unit : it can get Munin's vlabel as unit, but I don't like it, so I prefer to not send unit.
