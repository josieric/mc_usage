## mc_usage
* multicast info on host usage  
./mc_usage.pl <server|shutdown|listhost|client|execute> \[<degree of parallelism> <commands file or commands>\]  
	Execute commands on a list of hosts who send their usage to a multicast group.  
	Server : Multicast usage (%cpu, %vsz) to a multicast group.  
	Clients: Choose a target host to execute commands (via ssh).  
	see mc_usage_initd to start/stop the mc usage server at boot time  
	Create config file: touch mc_server_env.sh && chmod +x mc_server_env.sh  

-	Environment variables;  
		export MCGROUP=<MulticastGroup> (default:239.11.11.11)  
		export MCPORT=<MulticastPort> (default:45688)  
		export MCSERVERSLEEP=<sleep time for mc server> (default:5)  
		export MCEXECSLEEP=<sleep time for wait child in ModeExecute> (default:1)  
		export ONE_MULTICAST=1 (default:0) use in ModeExecute to single request to MCGROUP:PORT  
				so host is elected by roundrobin  
-	Command: server  
		start the multicast server to send usage info (log to mc_server.log)  
-	Command: shutdown  
		shutdown the multicast server if it is on the same host  
-	Command: shutdownall  
		shutdown the multicast server on all hosts (kill via ssh)  
-	Command: lishost  
		read multicast to find a list of ALL host in this MCGROUP:MCPORT  
-	Command: client  
		read multicast to find host with lower usage  
-	Command: execute  
		execute commands on lower usage host (log to mc_execute.log)  
		When execute: 4th parameter is the max number of child (degree of parallelism)  
		When execute: 5th parameter is a file of commands or a list of commands to run  

* Exemple:
./mc_usage.pl server  
./mc_usage.pl shutdown  
./mc_usage.pl client  
./mc_usage.pl execute 1 "sleep 5 ; echo 1111" "sleep 5 ; echo 2222"  
./mc_usage.pl execute 2 "sleep 20 ; echo 1111" "echo 2222"  
./mc_usage.pl execute 10 file_with_cmd_to_run.txt  

