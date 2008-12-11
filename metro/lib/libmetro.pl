# $Id: libmetro.pl,v 1.4 2008-12-11 14:15:03 boggia Exp $
###########################################################
#   Creation : 26/03/08 : boggia
# 
#Fichier contenant les fonctions g�n�riques des programmes
# de m�trologie
###########################################################

###########################################################
# fonction de lecture de fichier de conf
# prend un fichier de conf et une variable recherchee en param
# renvoie la valeur de la variable
# appelee par :
# read_conf_file("nom_fichier_conf","variable_recherchee"); 
#
sub read_conf_file
{
    my ($file,$var) = @_;

    my $line;

    open(CONFFILE, $file);
    while($line=<CONFFILE>)
    {
        if( $line!~ /^#/ && $line!~ /^\s+/)
        {
            chomp $line;
            my ($variable,$value) = (split(/\s+/,$line))[0,1];
            if($variable eq $var)
            {
                close(CONFFILE);
                return $value;
            }
        }
    }
    close(CONFFILE);

    return "UNDEF";
}

###########################################################
# fonction de lecture de la globalite du fichier de conf
# prend un fichier de conf et stocke la totalit� des
# variables du un tableau associatif
sub read_global_conf_file
{
    my ($file) = @_;
    
    my $line;

    open(CONFFILE, $file);
    while($line=<CONFFILE>)
    {
	if( $line!~ /^#/ && $line!~ /^\s+/)
	{   
	    chomp $line;
	    my ($variable,$value) = (split(/\s+/,$line))[0,1];

	    $var{$variable} = $value;
	}
    }
    close(CONFFILE);

    return %var;
}

###########################################################
# fonction de nettoyage de chaines de caract�res
# enl�ve les espaces � la fin d'une chaine de char
sub clean_var
{
    my ($string) = @_;

    my $s = $string;
    my $test = chop $s;
    
    if($test eq " ")
    {
	$string = $s;	
    }

    return $string;
}


###########################################################
# conversion des d�bits max en bits/s en X*10eY
# 100000000 -> 1.0000000000+e08
sub convert_nb_to_exp
{
    my ($speed) = @_;

    if($speed=~/[0-9]+/)
    {
        my @chiffres = split(//,$speed);
        my $nb_exp = "$chiffres[0].";
        my $t_chiffres = @chiffres;
        my $i;
        for($i=1;$i<11;$i++)
        {
            if($chiffres[$i])
            {
                $nb_exp = "$nb_exp" . "$chiffres[$i]";
            }
            else
            {
                $nb_exp = "$nb_exp" . "0";
            }
        }
        $t_chiffres --;
        if($t_chiffres < 10)
        {
            $nb_exp = "$nb_exp" . "e+0$t_chiffres";
        }
        else
        {
            $nb_exp = "$nb_exp" . "e+$t_chiffres";
        }
        return $nb_exp;
    }
    else
    {
        return -1;
    }
}

###########################################################
# donne une limite de d�bit maximum aux mesures inscrites 
# dans une base
sub setBaseMaxSpeed
{
    my ($base,$speed) = @_;
    my $maxspeed = convert_nb_to_exp($speed);
    system("/usr/local/bin/rrdtool tune $base --maximum input:$maxspeed");
    system("/usr/local/bin/rrdtool tune $base --maximum output:$maxspeed");
}

###########################################################
# retourne la vitesse d'une interface
#sub get_snmp_ifspeed
#{
#    my ($param,$index) = @_;

#    &snmpmapOID("speed","1.3.6.1.2.1.2.2.1.5.$index");
#    my @speed = &snmpget($param, "speed");

#    if($speed[0] ne "")
#    {
#        return $speed[0];
#    }
#    else
#    {
#        writelog("cree-base-metro","","info",
#            "\t ERREUR : Vitesse de ($param,index : $index) non definie, force � 100 Mb/s");
#        return 100000000;
#    }
#}


###########################################################
# retourne la vitesse d'une interface
sub get_snmp_ifspeed
{
    my ($param,$index,$interf) = @_;

    my $speed;

    # recherche de l'interface dans le tableau des interfaces
    foreach my $key (keys %if_speed)
    {
        if($interf=~/$key/)
        {
                $speed = $if_speed{$key};
        }
    }

    # si le nom de l'interface ne matche pas les interfaces connues
    if($speed eq "")
    {
        if($index eq "")
        {
                # recuperation de l'oid de l'interface
                $index = get_snmp_ifindex($param,$interf);
        }
        #&snmpmapOID("speed","1.3.6.1.2.1.2.2.1.5.$index");
        &snmpmapOID("speed","1.3.6.1.2.1.31.1.1.1.15.$index");
        my @speed = &snmpget($param, "speed");
        $speed = $speed[0];
    }

    if($speed ne "")
    {
        $speed = $speed*1000000;

        return $speed;
    }
    else
    {
        writelog("cree-base-metro","","info",
            "\t ERREUR : Vitesse de ($param,$interf,index : $index) non definie, force � 100 Mb/s");
        return 100000000;
    }
}



###########################################################
# creation de la Base RRD pour le trafic sur un port ainsi 
# que la disponibilite reseau
sub creeBaseTrafic
{
    my ($fichier,$speed)=@_;
    system("/usr/local/bin/rrdtool create $fichier  DS:input:COUNTER:600:U:U DS:output:COUNTER:600:U:U DS:erreur:GAUGE:600:U:U DS:ticket:GAUGE:600:U:U RRA:AVERAGE:0.5:1:525600 RRA:AVERAGE:0.5:24:43800 RRA:MAX:0.5:24:43800");
    setBaseMaxSpeed($fichier,$speed);
}

###########################################################
# creation d'une base RRD de trafic sp�cifique aux points
# d'acces
sub creeBaseOsirisAP
{
    my ($fichier,$speed)=@_;
    system("/usr/local/bin/rrdtool create $fichier DS:input:COUNTER:600:U:U DS:output:COUNTER:600:U:U RRA:AVERAGE:0.5:1:210240 RRA:AVERAGE:0.5:24:43800 RRA:MAX:0.5:24:43800");
    setBaseMaxSpeed($fichier,$speed);
}

###########################################################
# creation d'une base d'associations aux AP
sub creeBaseApAssoc
{
    my ($fichier)=@_;
        system("/usr/local/bin/rrdtool create $fichier DS:wpa:GAUGE:600:U:U DS:clair:GAUGE:600:U:U RRA:AVERAGE:0.5:1:210240 RRA:AVERAGE:0.5:24:43800 RRA:MAX:0.5:24:43800");
}

###########################################################
# METROi : creation d'une base d'associes ou d'authentifies 
# pour un AP WiFi
sub creeBaseAuthassocwifi
{
    my ($fichier,$ssid)=@_;

    system("/usr/local/bin/rrdtool create $fichier DS:$ssid:GAUGE:600:U:U RRA:AVERAGE:0.5:1:210240 RRA:AVERAGE:0.5:24:43800 RRA:MAX:0.5:24:43800");
}

###########################################################
# fonction de creation d'une base RRD pour une collecte des 
# donnees en % de la CPU
sub creeBaseCPU
{
    my ($fichier)=@_;
        system("/usr/local/bin/rrdtool create $fichier DS:cpu_system:GAUGE:600:U:U DS:cpu_user:GAUGE:600:U:U RRA:AVERAGE:0.5:1:210240 RRA:AVERAGE:0.5:24:43800 RRA:MAX:0.5:24:43800");
}

###########################################################
# fonction de creation d'une base RRD pour la collecte du 
# nombre d'interruptions systeme d'une machine
sub creeBaseInterupt
{
    my ($fichier)=@_;
        system("/usr/local/bin/rrdtool create $fichier DS:interruptions:GAUGE:600:U:U RRA:AVERAGE:0.5:1:210240 RRA:AVERAGE:0.5:24:43800 RRA:MAX:0.5:24:43800");
}

###########################################################
# fonction de creation d'une base RRD pour la collecte du
# load average d'une machine
sub creeBaseLoad
{
    my ($fichier)=@_;
        system("/usr/local/bin/rrdtool create $fichier DS:load_5m:GAUGE:600:U:U DS:load_15m:GAUGE:600:U:U RRA:AVERAGE:0.5:1:210240 RRA:AVERAGE:0.5:24:43800 RRA:MAX:0.5:24:43800");
}

###########################################################
# fonction de creation d'une base RRD pour la collecte de
# l'utilisation de la memoire et du swap
sub creeBaseMemory
{
    my ($fichier)=@_;
        system("/usr/local/bin/rrdtool create $fichier DS:memoire:GAUGE:600:U:U DS:swap:GAUGE:600:U:U RRA:AVERAGE:0.5:1:210240 RRA:AVERAGE:0.5:24:43800 RRA:MAX:0.5:24:43800");
}

###########################################################
# fonction de creation d'une base RRD pour la collecte de
# l'utilisation de la CPU d'un �quipement Cisco
sub creeBaseCPUCisco
{
    my ($fichier)=@_;
    system("/usr/local/bin/rrdtool create $fichier DS:cpu_1min:GAUGE:600:U:U DS:cpu_5min:GAUGE:600:U:U RRA:AVERAGE:0.5:1:210240 RRA:AVERAGE:0.5:24:43800 RRA:MAX:0.5:24:43800");
    system("chown obj999:obj999 $fichier");
}

###########################################################
# fonction  qui cr�e une base qui stocke les stats du d�mon
# bind
sub creeBaseBind_stat
{
($fichier)=@_;
        system("/usr/local/bin/rrdtool create $fichier DS:success:COUNTER:600:U:U DS:failure:COUNTER:600:U:U DS:nxdomain:COUNTER:600:U:U DS:recursion:COUNTER:600:U:U DS:referral:COUNTER:600:U:U DS:nxrrset:COUNTER:600:U:U RRA:AVERAGE:0.5:1:525600 RRA:AVERAGE:0.5:24:43800 RRA:MAX:0.5:24:43800");
        system("/usr/local/bin/rrdtool tune $fichier --maximum success:3.0000000000e+04");
        system("/usr/local/bin/rrdtool tune $fichier --maximum failure:3.0000000000e+04");
        system("/usr/local/bin/rrdtool tune $fichier --maximum nxdomain:3.0000000000e+04");
        system("/usr/local/bin/rrdtool tune $fichier --maximum recursion:3.0000000000e+04");
        system("/usr/local/bin/rrdtool tune $fichier --maximum referral:3.0000000000e+04");
        system("/usr/local/bin/rrdtool tune $fichier --maximum nxrrset:3.0000000000e+04");
}

sub creeBaseTPSDisk
{
($fichier)=@_;
    system("/usr/local/bin/rrdtool create $fichier DS:ioreads:COUNTER:600:U:U DS:iowrites:COUNTER:600:U:U RRA:AVERAGE:0.5:1:210240 RRA:AVERAGE:0.5:24:43800 RRA:MAX:0.5:24:43800");
    system("/usr/local/bin/rrdtool tune $fichier --maximum ioreads:1.0000000000e+06 iowrites:1.0000000000e+06");
}


sub creeBaseMailq
{
($fichier)=@_;
        system("/usr/local/bin/rrdtool create $fichier DS:mailq:GAUGE:600:U:U RRA:AVERAGE:0.5:1:210240 RRA:AVERAGE:0.5:24:43800 RRA:MAX:0.5:24:43800");
}

sub creeBaseOsirisCE
{
($fichier)=@_;
        system("/usr/local/bin/rrdtool create $fichier  DS:input:COUNTER:600:U:U DS:output:COUNTER:600:U:U DS:erreur:GAUGE:600:U:U DS:ticket:GAUGE:600:U:U RRA:AVERAGE:0.5:1:525600 RRA:AVERAGE:0.5:24:43800 RRA:MAX:0.5:24:43800");
        system("/usr/local/bin/rrdtool tune $fichier --maximum input:2.0000000000e+09 output:2.0000000000e+09");
}

###########################################################
# fonction de creation d'une base RRD pour la collecte de
# de valeurs en secondes sous forme de jauge
sub creeBaseTpsRepWWW
{
($fichier)=@_;
    system("/usr/local/bin/rrdtool create $fichier DS:time:GAUGE:600:U:U RRA:AVERAGE:0.5:1:210240 RRA:AVERAGE:0.5:24:43800 RRA:MAX:0.5:24:43800");
}

###########################################################
# fonction de creation d'une base RRD pour la collecte de
# de valeurs en secondes sous forme de jauge pour une
# interrogation toutes les minutes
sub creeBaseTpsRepWWWFast
{
($fichier)=@_;
    system("/usr/local/bin/rrdtool create $fichier -s 60 DS:time:GAUGE:120:U:U RRA:AVERAGE:0.5:1:1051200 RRA:AVERAGE:0.5:60:43800 RRA:MAX:0.5:60:43800");
}

###########################################################
# fonction de creation d'une base RRD pour la collecte de
# de valeurs en octets sous forme de jauge
sub creeBaseVolumeOctets
{
($fichier)=@_;
    system("/usr/local/bin/rrdtool create $fichier DS:octets:GAUGE:600:U:U RRA:AVERAGE:0.5:1:210240 RRA:AVERAGE:0.5:24:43800 RRA:MAX:0.5:24:43800");
}

###########################################################
# fonction de creation d'une base RRD pour la collecte de
# de valeurs en octets sous forme de jauge
sub creeBaseNbMbuf
{
($fichier)=@_;
    system("/usr/local/bin/rrdtool create $fichier DS:mbuf:GAUGE:600:U:U RRA:AVERAGE:0.5:1:210240 RRA:AVERAGE:0.5:24:43800 RRA:MAX:0.5:24:43800");
}

###########################################################
# fonction de creation d'une base RRD pour la collecte de
# de valeurs en octets sous forme de jauge
sub creeBaseNbGeneric
{
($fichier)=@_;
    system("/usr/local/bin/rrdtool create $fichier DS:value:GAUGE:600:U:U RRA:AVERAGE:0.5:1:210240 RRA:AVERAGE:0.5:24:43800 RRA:MAX:0.5:24:43800");
}

###########################################################
# fonction de creation d'une base RRD pour la collecte de
# de valeurs en octets sous forme de jauge pour une
# interrogation toutes les minutes
sub creeBaseVolumeOctetsFast
{
($fichier)=@_;
    system("/usr/local/bin/rrdtool create $fichier DS:octets:GAUGE:120:U:U RRA:AVERAGE:0.5:1:210240 RRA:AVERAGE:0.5:24:43800 RRA:MAX:0.5:24:43800");
}



return 1;
