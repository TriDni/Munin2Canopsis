Munin2Canopsis
==============

This script is a connector for Canopsis. It allows to send in real time Munin's datas to Canopsis.
Note : Sorry for my bad english, i'm french ;) 

French documentation is here : http://triden.org

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

Take care to have enough space for MongoDB, and to not have more than 15000 RRDs to send to Canopsis (I think it could work with a little more RRDs but I haven't precisely measure it).
Execute the following command to know how many RRD files you have) :

    find /var/lib/munin/ -type f | wc -l  

Indeed, RabbitMQ could queue AMQP messages if you have too much of these. To verify your server capacity you can time the script and make sure that it takes less than 4-5 min to execute (munin-update time period).

    time ./munin2Canopsis.pl

Actually, it doesn't send any perdata unit : it can get Munin's vlabel as unit, but I don't like it, so I prefer to not send unit.

I had realized a Python's version of this script, but I think you should use Perl's version because it runs really faster than Python's. I think because a lot of regexp are used to do the job (everybody knows that Perl is better in regexp ! :) )

insertMuninData
===============

This script allows to inject some Munin's plugin Datas in Canopsis. It scans Munin's datafile and via some forms you can choose some plugins and the time period you want to import to Canopsis.

##Requirements

    sudo apt-get install make libclass-data-inheritable-perl libtest-deep-perl libmoosex-app-cmd-perl libcoro-perl libjson-xs-perl libxml-libxml-perl libconfig-any-perl libmoosex-attributehelpers-perl libmoosex-configfromfile-perl libtest-exception-perl libfile-sharedir-perl libreadonly-xs-perl libuuid-tiny-perl
    cpan -i Net::RabbitFoot
    cpan -i JSON::XS
    cpan -i Term::Pager
    cpan -i Term::ReadKey
    cpan -i HTTP::Date
    
##Usage

You can modify settings in script's head (like munin2Canopsis.pl script).
Just launch it and complete forms :

    ./insertMuninData.pl
    
In this form, you have to give some informations : first step is to search component (server or munin-node) which is interesting for you. Then select any of the generated list via ID.
Second step is to select resource (Munin's plugin) among list available. 
Last step is to select a begin and end datetime period (if you let these field empty, all data will be injected to Canopsis).

Warning : You have to wait 5-10 minutes to see changes in Canopsis Web UI.

MuninSSH2Local
==============

These two scripts allow to get remote server's Munin Data through SSH on a local server (Canopsis). It's usefull if your remote server can't connect to your RabbitMQ and if you can only use SSH way.
The script on the remote server will get Munin's Data and will print it as encoded JSON string. You just have to use pipe and get STDIN with the script which is used in your local server (Canopsis). This local script will send data to RabbitMQ.

##Requirements

On the remote server (Munin), you just need JSYNC CPAN library : 

    cpan -i JSYNC
    
On the local server (Canopsis), you need common library needed to send Data to RabbitMQ :

    sudo apt-get install make libclass-data-inheritable-perl libtest-deep-perl libmoosex-app-cmd-perl libcoro-perl libjson-xs-perl libxml-libxml-perl libconfig-any-perl libmoosex-attributehelpers-perl libmoosex-configfromfile-perl libtest-exception-perl libfile-sharedir-perl libreadonly-xs-perl libuuid-tiny-perl
    cpan -i Net::RabbitFoot
    cpan -i JSON::XS
    cpan -i JSYNC
    
##Usage

You can use options to set the script :

    --domain           munin-node to filter (like localdomain, folder in /var/lib/munin/)
    --munin-path       root path of munin RRD (default : /var/lib/munin/)
    --help or help     show this
    
You can test "postMan.pl", normally it will print a big JSON STRING object. If you don't want to send all datas, you can use domain filter : it allows to send only datas for setted domain, munin-node (like "localdomain").

On the local server, edit head variable (RabbitMQ connection informations and the connector name like "Munin - remote server").

    my $rabbit_address = "127.0.0.1";
    my $rabbit_port = 5672;
    my $rabbit_user = "guest";
    my $rabbit_pwd = "guest";
    my $connector = "Munin - Remote server";


To execute import, this is an example :

    ssh user@remoteserver.org ./postMan.pl | ./postOffice.pl
    
In this case, "postMan.pl" is located in home of "user" user in the remote server (modify with your own path). 
"postOffice.pl" is in current directory in local server.

This command is executed on local server.
