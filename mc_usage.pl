#!/usr/bin/perl
#
# Usage:
# ./mc_usage.pl
#

use strict;
use IO::Socket::Multicast;
use Fcntl;
use Sys::Hostname;
use IO::Interface::Simple;

use constant EXEC_SSH => 'ssh -o PubkeyAuthentication=yes -o BatchMode=yes -o StrictHostKeyChecking=no ';
use constant DFGROUP => '239.11.11.11'; ## group multicast par default 
use constant DFPORT => '45688';         ## port multicast par default
use constant MCSERVERSLEEP => '5'; ## Temps en seconde de latence lors des attentes du server multicast
use constant MCEXECSLEEP => '1'; ## Temps en seconde de latence lors des attentes des fils en mode Execute (Wait_All & Wait_One)
use constant LOGDIR => '.';

use vars qw($latence $server_sleep_time);
$latence = $ENV{"MCEXECSLEEP"} || MCEXECSLEEP;
$server_sleep_time = $ENV{"MCSERVERSLEEP"} || MCSERVERSLEEP;

my $GROUP = $ENV{"MCGROUP"} || DFGROUP;
my $PORT  = $ENV{"MCPORT"} || DFPORT;
my $type = shift;
my $paral_max = shift || 1; # nombre de fils en parallele au max
my $cmdfile = shift;
$cmdfile="" if (! defined $cmdfile);

my $one_multicast = $ENV{"ONE_MULTICAST"} || 0;
$one_multicast = 1 if ($one_multicast != 0);

if ($type eq "server") {
  my $pid=fork();
  if (defined $pid && $pid == 0) {
    ## Ici on est dans le fils
    mc_server($GROUP.":".$PORT);
  }
  else {
    ## Ici le pere !!
    sleep 1;
    print "serveur launched $pid\n";
  }
}
elsif ($type =~ /^shutdown/ ) {
  ## Mode client/shutdown
  mc_client($GROUP,$PORT,$type);
}
elsif($type eq "listhost") {
  ## Mode client/listhost
  foreach(mc_client($GROUP,$PORT,$type)) {
    my ($h,$p,$ip) = split('/',$_);
    print $h." ($p) (".$ip.")\n";
  }
}
elsif($type eq "execute") {
  if ($paral_max !~ /^[0-9]*$/ ) {
    print "Degree of parallelism must be an integer !!\n";
    Usage();
  }
  my @liste=();
  if ( -f $cmdfile ) {
    Read_File(\@liste,$cmdfile);
  }
  elsif ($cmdfile ne "") {
    push(@liste,$cmdfile);
    push(@liste,@ARGV); # cas multi commandes sur la ligne de commande
  }
  else {
    push (@liste, 'hostname;pwd','sleep 2 ; whoami')
  }
  # Lance le bouzin Go Go Go !! :-)
  # Attention variable $one_multicast
  # permet de choisir le mode de recup du host d'execution
  # Mode round robin
  # MC 1 fois puis round robin
  # OU
  # Mode choix "lower usage"
  # MC avant chaque lancement de commande
  GoGoGo($GROUP,$PORT,$paral_max,\@liste,$one_multicast);

## sortie des fils
## Passage getparam ??
## puce leonard
## 
}
elsif($type eq "client") {
  ## Mode client
  mc_client($GROUP,$PORT);
}
else {
  Usage();
}

#################
## Functions 
#######################
sub Usage {
  print "$0 <server|shutdown|listhost|client|execute> [<degree of parallelism> <commands file or commands>]\n";
  print "\tExecute commands on a list of hosts who send their usage to a multicast group.\n";
  print "\tServer : Multicast usage (\%cpu, \%vsz) to a multicast group.\n";
  print "\tClients: Choose a target host to execute commands (via ssh).\n";
  print "\tsee mc_usage_initd to start/stop the mc usage server at boot time\n\tCreate config file: touch mc_server_env.sh && chmod +x mc_server_env.sh\n";
  print "\n\tEnvironment variables;\n\t\texport MCGROUP=<MulticastGroup> (default:".DFGROUP.")\n\t\texport MCPORT=<MulticastPort> (default:".DFPORT.")\n";
  print "\t\texport MCSERVERSLEEP=<sleep time for mc server> (default:".MCSERVERSLEEP.")\n\t\texport MCEXECSLEEP=<sleep time for wait child in ModeExecute> (default:".MCEXECSLEEP.")\n";
  print "\t\texport ONE_MULTICAST=1 (default:0) use in ModeExecute to single request to MCGROUP:PORT\n\t\t\t\tso host is elected by roundrobin\n";
  print "\tCommand: server\n";
  print "\t\tstart the multicast server to send usage info (log to mc_server.log)\n";
  print "\tCommand: shutdown\n";
  print "\t\tshutdown the multicast server if it is on the same host\n";
  print "\tCommand: shutdownall\n";
  print "\t\tshutdown the multicast server on all hosts (kill via ssh)\n";
  print "\tCommand: lishost\n";
  print "\t\tread multicast to find a list of ALL host in this MCGROUP:MCPORT\n";
  print "\tCommand: client\n";
  print "\t\tread multicast to find host with lower usage\n";
  print "\tCommand: execute\n";
  print "\t\texecute commands on lower usage host (log to mc_execute.log)\n";
  print "\t\tWhen execute: 4th parameter is the max number of child (degree of parallelism)\n";
  print "\t\tWhen execute: 5th parameter is a file of commands or a list of commands to run\n";
  print "\nExemple:\n$0 server\n";
  print "$0 shutdown\n";  
  print "$0 client\n";
  print "$0 execute 1 \"sleep 5 ; echo 1111\" \"sleep 5 ; echo 2222\"\n";
  print "$0 execute 2 \"sleep 20 ; echo 1111\" \"echo 2222\"\n";
  print "$0 execute 10 file_with_cmd_to_run.txt\n";
  exit 1;
}

#################
## Functions multicast
#######################
sub mc_client {
  my $GROUP = shift;
  my $PORT  = shift;
  my $action = shift;
  my $logname = shift;
  my $time_in=time();
  my $sock = IO::Socket::Multicast->new(Proto=>'udp',LocalPort=>$PORT);
  while ( ! $sock ) {
     Log($logname, format_dt(time)." Error opening localport $PORT : $!\n");
     Log($logname, "\tRetry in $server_sleep_time s\n");
     sleep $server_sleep_time;
     $sock = IO::Socket::Multicast->new(Proto=>'udp',LocalPort=>$PORT);
  }
  $sock->mcast_ttl(1);
  $sock->mcast_add($GROUP) || die "Couldn't set group: $!\n";
  binmode $sock;
  my $flags;
  fcntl($sock, F_GETFL, $flags) || die $!; # Get the current flags on the filehandle
  fcntl($sock, F_SETFL, $flags | O_NONBLOCK) || die $!; # Set the flags on the filehandle

  Log($logname, format_dt(time)." ModeClient $action $GROUP:$PORT ... ...\n");
  my $timeout=$server_sleep_time + 2; # Et pourquoi pas 2 !!
  my $time = time();
  my $choix = {};
  while (1) {
     my $data;
      unless ($sock->recv($data,512) )  {
       sleep 1;
       if (time() - $time > $timeout) {
         die "Nobody speak since $timeout s.\n";
         #last;
       }
       next;
     }
     $time = time();
     my ($ip1,$ip2,$ip3,$ip4,$recv_time,$cpu_usage,$mem_usage,$pid,$host) = unpack('C4lffIa*',$data);
     Log($logname, format_dt($time) ." ".  $host ."/$ip1.$ip2.$ip3.$ip4/". $pid ."\t". round($cpu_usage) ."\t". round($mem_usage) ."\n");
     $host = $host."/".$pid;
     if (! defined $choix->{$host} ) {
       $choix->{$host}->{CPU} = $cpu_usage;
       $choix->{$host}->{MEM} = $mem_usage;
       $choix->{$host}->{IP} = "$ip1.$ip2.$ip3.$ip4";
     }
     else {
       last;
     }
  }
  $sock->mcast_drop($GROUP) || die "Couldn't unset group: $!\n";
  $sock->close()  || die "Couldn't stop socket: $!\n";
  if ($action =~ /^shutdown/) {
    foreach(keys %{$choix}) {
      my ($host,$pid) = split('/',$_);
      my $hostname=hostname();
      if ($host eq $hostname) {
        print $type." pid ".$pid."\n";
        kill INT => $pid;
      }
      else {
        print "ssh $host \"kill $pid\"\n";
        ssh($host,"kill $pid") if ($action eq "shutdownall");
      }
    }
  }
  else { ## Cas par defaut command client et list host
    # Tri par la charge CPU
    my @list = sort { $choix->{$a}->{CPU} <=> $choix->{$b}->{CPU} } keys %{$choix};
    my $host_elected = $list[0];
    if ( $choix->{$host_elected}->{CPU} > 50) {
      # Tri par charge memoire
      @list = sort { $choix->{$a}->{MEM} <=> $choix->{$b}->{MEM} } keys %{$choix};
      $host_elected = $list[0];
    }
    my $elapse = time() - $time_in;
    if ($action eq "listhost") {
      ## return pour le cas listhost
      foreach(@list) {
         $_ .=  "/".$choix->{$_}->{IP};
      }
      Log($logname, format_dt($time) ." ". ($#list+1) ." servers (elapse:${elapse}s)\n");
      return @list ;
    }
    else {
      ## return pour le cas execute
      Log($logname, format_dt($time) ." Elected -> ".$host_elected."/".$choix->{$host_elected}->{IP}." (elapse:${elapse}s)\n");
      return $host_elected."/".$choix->{$host_elected}->{IP} ;
    }
  }
}


sub mc_server_die {
  Log("mc_server",format_dt(time())." Outta here! SIG@_ received\n");
  die "bye\n";
}
sub mc_server {
  $SIG{INT} = \&mc_server_die;
  my $DESTINATION=shift;
  my $hostname=hostname();

  open(MEMINFO,"<","/proc/meminfo");
  my ($memtotal) = grep { /MemTotal/ } <MEMINFO>;
  close(MEMINFO);
  chomp($memtotal);
  $memtotal =~ s/^[^0-9]*([0-9]*).*$/\1/;

  my $nbcpu = `grep processor /proc/cpuinfo | wc -l`;
  chomp($nbcpu);
  my @miip = split(/\./,get_public_ip());
  Log("mc_server", format_dt(time())."\nIP=".join(".",@miip)."\npid=$$\nDestination=$DESTINATION\nHost=$hostname\ncpu=$nbcpu\nmem=$memtotal\n");

  my $sock = IO::Socket::Multicast->new(Proto=>'udp',PeerAddr=>$DESTINATION);
  binmode $sock;
  $sock->mcast_ttl(1);
  while (1) {
    my $time=time();
    my $sum_c=0;
    my $sum_m=0;
    #ps % cpu & memo vsz in Kb
    foreach(`ps -eo "%C %z"`) {
      my @tmp = split(" ",$_);
      $sum_c += $tmp[0];
      $sum_m += $tmp[1];
    }
    $sum_m = round(($sum_m/$memtotal)*100); # tant pis pour la shared mem !!!
    $sum_c = $sum_c/$nbcpu;

    #print format_dt($time)."\t$hostname-$$\t$sum_c\t$sum_m\n";
    $sock->send(pack('C4lffIa*',@miip,$time,$sum_c,$sum_m,$$,$hostname)) || die "Couldn't send: $!";
  } continue {
    sleep $server_sleep_time;
  }
}

sub get_public_ip {
  foreach( IO::Interface::Simple->interfaces ) {
    if( $_->is_running && defined $_->address && $_->address ne "127.0.0.1") {
      return $_->address;
    }
  }
}

#################
## Functions generales
#######################
sub round {
  my $nb = shift;
  return int(($nb*100) + 0.5) /100;
}
sub format_dt {
  # Formatage de la date
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($_[0]);
  $year += 1900;
  $mon++;
  $mday = "0".$mday if (length($mday) == 1 );
  $mon = "0".$mon   if (length($mon)  == 1 );
  $hour = "0".$hour if (length($hour) == 1 );
  $min = "0".$min   if (length($min)  == 1 );
  $sec = "0".$sec   if (length($sec)  == 1 );
  return "$year-$mon-$mday $hour:$min:$sec";
}
	
sub Log {
  my $logname=shift;
  my $message = shift;
  print $message;
  if (defined $logname && $logname ne "") {
    open(FLOG,">>",LOGDIR."/".$logname.".log");
    print FLOG $message;
    close(FLOG);
  }
}

sub ssh {
  my $user_host=shift;
# Puce leonard
$user_host="hello@".$user_host if ($user_host eq "192.168.0.103" || $user_host eq "leonard");
  my $cmd=shift;
  my $out;
  open($out, EXEC_SSH."$user_host \"$cmd 2>&1\" 2>&1 |");
  while(<$out>) {
    print $_;
  }
  close($out);
}

##############
## Fonction fork et suivi des fils
####################################
sub Read_File {
   ## Lecture "bete" du fichier parametre
   ## Chaque ligne est considéré comme une commande à lancer
   my $liste=shift;   # Reference du tableau "liste des commandes"
   my $fileparam=shift;  # Nom du fichier
   # Ouverture en lecture du fichier
   open FIC, "<".$fileparam;
   while(<FIC>) { # Lecture ligne à ligne du fichier. La ligne se trouve dans la variable de contexte : $_
     chomp($_); # vire le retour chariot.
     push(@{$liste},$_); # On ajoute la ligne dans le tableau.
   }
   # Fermeture du fichier de param
   close FIC;
}


sub GoGoGo { ## Il s'agit de la procedure principale qui fait le pere et ses fils
  my $GROUP=shift;
  my $PORT=shift;
  my $numforks = shift;  ## Nombre de process // à lancer (param 1)
  my $liste = shift;           ## reference de la liste de commandes à lancer (param 2)
  my $only1mc = shift;
  my $childs;  ## Reference du tableau de HASH qui contient les pid des fils et infos
  ## Description de l'utilisation de $childs
  ## $childs->{$processID}	identifiant de chaque fils
  ## 		->{"cmd"}	contient la commande à lancer
  ##		->{"timedeb"}	contient le timestamp de debut de process
  ##		->{"num"}	contient le d'ordre de lancement
  ##		->{"host"}	contient le nom de la machine d'execution
  ##		-> ... On peut ajouter au besoin des infos sur les fils.
  my $nbfils = 0;	       ## Nombre de fils en cours d'execution
  my $nbcmd = 0;	       ## Nombre de commandes lancées
  my $timedeb = time;	       ## time du debut de vie du pere
  my @hostdispo = ();          ## liste des machine qui envoi dans le GROUP MULTICAST utilisé utile dans le cas roundrobin ($only1mc)
  if ($only1mc) {
    @hostdispo = mc_client($GROUP,$PORT,"listhost","mc_execute"); # get all hosts
  }
  foreach(@{$liste}) {  # Pour chaque commande de la liste
    my $cmd=$_;
    my ($hostname,$hostip);
    if ($only1mc) {
      my $foo;
      my $i = $nbcmd % ($#hostdispo + 1);
      ($hostname,$foo,$hostip) = split('/',$hostdispo[$i]); # choix dans les hosts dispo dans l'unique requete multicast du debut
    }
    else {
      my $foo;
      ($hostname,$foo,$hostip) = split('/',mc_client($GROUP,$PORT,"client","mc_execute")); # determine la machine avec lower usage
    }
    my $pid;
    while (! defined $pid) {  ## Tant que le fils n'est pas lancé
      $pid = fork();          ## fork !!! (IE vite fait : création d'un fils qui commence sa "vie" à la ligne suivante (si $pid==0)
			      ## pendant que le pere fait de meme en //)  (si $pid != 0 et contient donc le ProcessID.)
      if (! defined $pid) {   ## Le fils est-il lancé ?? (Ben oui si $pid est indefini alors: y'a pas bon!).
        Log("mc_execute", "\tCannot fork: $!\n");
        Check_Childs($childs);
        sleep $latence;
        Log("mc_execute", "\tRetry..\n");  ## Ou aussi
			## die "ERROR:\n$!\n$^E\n$?\n";
      }
    }
    ## Ici le fils est lancé
    if (defined $pid && $pid == 0) {
      ## Ici on est dans le fils
      ## du coup on lance la commande "current" de la liste
      Log("mc_execute", format_dt(time)." \tPID=$$ call on $hostip -> ssh $hostname \"$cmd\"\n");
      ## on appel ssh via l'OS pour le lancement de la commande
      ssh($hostip, $cmd);
      exit; ## ET SURTOUT ON SORT CAR ON EST LE FILS
    }
    else {
      ## Ici le pere
      ## Donc on gére le tableau de HASH des fils et le nombre de commandes lancées
      $nbcmd++;
      $childs->{$pid}->{"cmd"}=@{$liste}[$nbcmd];
      $childs->{$pid}->{"timedeb"}=time;
      $childs->{$pid}->{"host"}=$hostname;
      $childs->{$pid}->{"num"}=$nbcmd;
      Log("mc_execute", format_dt(time)." Process $nbcmd ($pid) started via $hostname\n");
      Check_Childs($childs);  ## On check un coup si y'a pas un fils qu'aurai fini
    }
    ## Ici on a checké les fils donc on annonce le nombre de fils en cours
    my @tmp = keys %{$childs};
    $nbfils=$#tmp + 1;
    Log("mc_execute", format_dt(time)." ".$nbfils." childs running ...\n");
    if ($nbfils == $numforks) {  ## Si le nombre de fils est egal au degré de //
      Log("mc_execute", format_dt(time)." Must Wait !!\n");
      Wait_One($childs);         ## On attend la fin d'au moins 1 fils
    }
  } # Fin du foreach des commandes à lancer
  Log("mc_execute", format_dt(time)." All commands ($nbcmd) were launched.\n");
  # On attend tous les fils restants
  Wait_All($childs);
  my $elapse=time - $timedeb;
  Log("mc_execute", format_dt(time)." Father finish. (Elapse: $elapse) :pPpP\n\n");
}

sub Check_Childs {
  #Check status des fils
  #retourne le tableau avec les fils restants
  # Detection de la fin des fils
  my $process = shift;
  while ( my ($p , $s) = each %{$process} ) {  # Pour l'ensemble des fils 
      my $ret = waitpid($p,1);  # Est ce qu'il est fini ??
      if ($ret != 0) {		# Le fils est terminé
        my $elapse = time - $s->{"timedeb"};
        Log("mc_execute", format_dt(time)." Process ".$s->{"num"}." ($p) finished (host:".$s->{"host"}." cmd:".$s->{"cmd"}.").\t(Elapse: $elapse)\n");
        delete $process->{$p};  # On supprime sa reference dans le tableau de HASH des fils
      }
  }
}

sub Wait_All {
  #wait all childs
  my $process = shift;
  my $encore=0;
  while ($encore >= 0) { # Tant qu'il y a encore des fils
    sleep $latence;
    Check_Childs($process);  # On check les fils
    my @tmp=keys %{$process}; # On regarde leur nombre encore présent
    $encore=$#tmp;            # Et on le stocke dans la variable encore
  }
}

sub Wait_One {
  #wait 1 (or more) child
  my $process = shift;
  my @nbfils=keys %{$process};  # Initialise le nombre de fils en cours
  my $reste=0;
  while ($reste == 0) {    # Tant qu'il n'y a pas au moins 1 fils qui a terminé
    sleep $latence;
    Check_Childs($process);  # On check les fils
    my @tmp=keys %{$process}; # Reprend le nombre restant de fils
    $reste=$#nbfils-$#tmp;    # On calcul si le reste de fils par rapport au début de fonction
  }
}

