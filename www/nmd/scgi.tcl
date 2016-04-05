#
# This file provides two packages to build a SCGI-based application
#
# It is in fact divided into 2 different packages:
# - scgiserver: this package contains only one function to
#	start the multi-threaded SCGI server
# - scgiapp: this package is implicitely loaded into each thread
#	started by the server (see thrscript)
#

package require Tcl 8.6
package require Thread 2.7

package provide scgiserver 0.1

namespace eval ::scgiserver:: {
    namespace export start

    ###########################################################################
    # Server connection and thread pool management
    ###########################################################################

    # thread pool id
    variable tpid

    # server configuration
    variable serconf
    array set serconf {
	-minworkers 2
	-maxworkers 4
	-idletime 30
	-myaddr 0.0.0.0
	-myport 8080
	-debug 1
    }


    #
    # Start a multi-threaded server to handle SCGI requests from the
    # HTTP proxy
    #
    # Usage:
    #	::scgiserver::start [options] init-script handle-function
    #	with standard options:
    #		-minworkers: minimum number of threads in thread pool
    #		-maxworkers: maximum number of threads in thread pool
    #		-idletime: idle-time for worker threads
    #		-myaddr: address to listen to connections
    #		-myport: port number to listen to connections
    #		-debug: get verbose error message
    #
    #	and arguments:
    #	- init-script: script to call in each worker thread. This script
    #		is called after creating the scgiapp package. Since
    #		each thread is created with a default Tcl interpreter
    #		(thus containing only the initial set of Tcl commands),
    #		the init-script should source a file containing the
    #		SCGI application itself.
    #	- handle-function: this is the name of a function inside the
    #		the SCGI application (thus in a worker thread) to
    #		handle a SCGI request from the HTTP proxy. This function
    #		is called with the following arguments:
    #
    #		XXXXXXXXXXXXXXXXX
    #

    proc start args {
	variable tpid
	variable serconf

	#
	# Get default parameters
	#

	array set p [array get serconf]

	#
	# Argument analysis
	#

	while {[llength $args] > 0} {
	    set a [lindex $args 0]
	    switch -glob -- $a {
		-- {
		    set args [lreplace $args 0 0]
		    break
		}
		-* {
		    if {[info exists p($a)]} then {
			set p($a) [lindex $args 1]
			set args [lreplace $args 0 1]
		    } else {
			error "invalid option '$a'. Should be 'server [array get serconf]'"
		    }
		}
		* {
		    break
		}
	    }
	}

	if {[llength $args] != 2} then {
	    error "invalid args: should be init-script handle-request"
	}

	lassign $args initscript handlereq

	variable thrscript

	set tpid [tpool::create \
			-minworkers $p(-minworkers) \
			-maxworkers $p(-maxworkers) \
			-idletime $p(-idletime) \
			-initcmd "$thrscript ;
				set ::scgiapp::handlefn $handlereq ;
				set ::scgiapp::debug $p(-debug) ;
				$initscript" \
		    ]

	socket \
	    -server [namespace code server-connect-hack] \
	    -myaddr $p(-myaddr) \
	    $p(-myport)

	vwait forever
    }

    proc server-connect-hack {sock host port} {
	after 0 [namespace code [list server-connect $sock $host $port]]
    }

    proc server-connect {sock host port} {
	variable tpid

	::thread::detach $sock
	set jid [tpool::post $tpid "::scgiapp::accept $sock $host $port"]
    }

    ###########################################################################
    # Connection handling
    #
    # Sub-package used for connections handled by each individual thread
    ###########################################################################

    variable thrscript {
	package require Thread 2.7
	package require ncgi 1.4
	package require json 1.1
	package require json::write 1.0

	namespace eval ::scgiapp:: {
	    namespace export accept \
			    get-header \
			    set-header set-body set-json set-cookie \
			    scgi-error \
			    output

	    #
	    # Name of the function (called in accept) to handle requests
	    # This variable is used in the ::scgiserver::start function.
	    #

	    variable handlefn

	    #
	    # Generate a Tcl stack trace in the message sent back
	    #

	    variable debug

	    #
	    # Global state associated with the current request
	    # - sock: socket to the client
	    # - reqhdrs: request headers
	    # - errcode: html error code, in case of error
	    # - rephdrs: reply headers
	    # - repbody: reply body
	    # - repbin: true if body is a binary format
	    # - done: boolean if output already done
	    #

	    variable state
	    array set state {
		sock {}
		reqhdrs {}
		errcode {}
		rephdrs {}
		repbody {}
		repbin {}
		done {}
	    }

	    #
	    # This function is called from the server thread
	    # by the ::scgiserver::server-connect function,
	    # indirectly by the tpool::post command.
	    # 

	    proc accept {sock host port} {
		variable handlefn
		variable debug
		variable state

		#
		# Get input socket
		#

		thread::attach $sock

		#
		# Reset global state
		#

		foreach k [array names state] {
		    set state($k) ""
		}
		set state(sock) $sock
		set state(done) false
		set state(errcode) 500

		try {
		    lassign [scgi-read $sock] state(reqhdrs) body

		    set parm [parse-param $state(reqhdrs) $body]
		    set cookie [parse-cookie]
		    set uri [get-header DOCUMENT_URI "/"]
		    set meth [string tolower [get-header REQUEST_METHOD "get"]]

		    $handlefn $uri $meth $parm $cookie

		} on error msg {

		    if {$state(errcode) == 500} then {
			set-header Status "500 Internal server error" true
		    } else {
			set-header Status "$state(errcode) $msg" true
		    }

		    if {$debug} then {
			set-body "<pre>Error during ::scgiapp::accept</pre>"
			set-body "\n<p>\n"
			global errorInfo
			set-body "<pre>$errorInfo</pre>"
		    } else {
			set-body "<pre>The server encountered an error</pre>"
		    }
		}

		try {
		    output
		    close $sock
		}
	    }

	    #
	    # Decode input according to the SCGI protocol
	    # Returns a 2-element list: {<hdrs> <body>}
	    #
	    # Exemple from: https://python.ca/scgi/protocol.txt
	    #	"70:"
	    #   	"CONTENT_LENGTH" <00> "27" <00>
	    #		"SCGI" <00> "1" <00>
	    #		"REQUEST_METHOD" <00> "POST" <00>
	    #		"REQUEST_URI" <00> "/deepthought" <00>
	    #	","
	    #	"What is the answer to life?"
	    #

	    proc scgi-read {sock} {
		fconfigure $sock -translation {binary crlf}

		set len ""
		# Decode the length of the netstring: "70:..."
		while {1} {
		    set c [read $sock 1]
		    if {$c eq ":"} then {
			break
		    }
		    append len $c
		}
		# Read the value (all headers) of the netstring
		set data [read $sock $len]

		# Read the final comma (which is not part of netstring len)
		set comma [read $sock 1]
		if {$comma ne ","} then {
		    error "Invalid final comma in SCGI protocol"
		}

		# Netstring contains headers. Decode them (without final \0)
		set hdrs [lrange [split $data \0] 0 end-1]

		# Get content_length header
		set clen [dget $hdrs CONTENT_LENGTH 0]

		set body [read $sock $clen]

		return [list $hdrs $body]
	    }

	    proc scgi-error {code reason} {
		variable state

		set state(errcode) $code
		error $reason
	    }

	    proc get-header {key {defval {}}} {
		variable state
		return [dget $state(reqhdrs) $key $defval]
	    }

	    proc set-header {key val {replace {true}}} {
		variable state

		set key [string totitle $key]
		set val [string trim $val]

		if {$replace || ![dict exists $state(rephdrs) $key]} then {
		    dict set state(rephdrs) $key $val
		}
	    }

	    proc set-body {data {binary false}} {
		variable state

		set state(repbin) $binary
		append state(repbody) $data
	    }

	    proc set-json {dict} {
		set-header Content-type application/json
		set-body [tcl2json $dict]
	    }

	    #
	    # See http://rosettacode.org/wiki/JSON#Tcl
	    #

	    proc tcl2json {value} {
		# Guess the type of the value; deep *UNSUPPORTED* magic!
		regexp {^value is a (.*?) with a refcount} \
		    [::tcl::unsupported::representation $value] -> type
	     
		switch $type {
		    string {
			return [json::write string $value]
		    }
		    dict {
			return [json::write object {*}[
			    dict map {k v} $value {tcl2json $v}]]
		    }
		    list {
			return [json::write array {*}[lmap v $value {tcl2json $v}]]
		    }
		    int - double {
			return [expr {$value}]
		    }
		    booleanString {
			return [expr {$value ? "true" : "false"}]
		    }
		    default {
			# Some other type; do some guessing...
			if {$value eq "null"} {
			    # Tcl has *no* null value at all; empty strings are semantically
			    # different and absent variables aren't values. So cheat!
			    return $value
			} elseif {[string is integer -strict $value]} {
			    return [expr {$value}]
			} elseif {[string is double -strict $value]} {
			    return [expr {$value}]
			} elseif {[string is boolean -strict $value]} {
			    return [expr {$value ? "true" : "false"}]
			}
			return [json::write string $value]
		    }
		}
	    }

	    proc output {} {
		variable state

		if {$state(done)} then {
		    return
		}

		if {$state(repbin)} then {
		    set clen [string length $state(repbody)]
		} else {
		    set clen [string bytelength $state(repbody)]
		}

		set-header Status "200" false
		set-header Content-type "text/html" false
		set-header Content-length $clen

		foreach {k v} $state(rephdrs) {
		    puts $state(sock) "$k: $v"
		}
		puts $state(sock) ""
		if {$state(repbin)} then {
		    flush $state(sock)
		    fconfigure $state(sock) -translation binary
		}
		puts -nonewline $state(sock) $state(repbody)

		catch {close $state(sock)}

		set state(done) true
	    }

	    #
	    # Extract parameters
	    # - hdrs: the request headers
	    # - body: the request body, as a byte string
	    #
	    # Returns dictionary
	    #

	    proc parse-param {hdrs body} {
		variable state

		set parm [dict create]

		set query [dget $hdrs QUERY_STRING]
		set parm [keyval $parm [split $query "&"]]

		if {$body eq ""} then {
		    dict set parm _bodytype ""
		} else {
		    lassign [content-type $hdrs] ctype charset
		    switch -- $ctype {
			{application/x-www-form-urlencoded} {
			    dict set parm _bodytype ""
			    set parm [keyval $parm [split $body "&"]]
			}
			{application/json} {
			    dict set parm _bodytype "json"
			    dict set parm _body [::json::json2dict $body]
			}
			default {
			    dict set parm _bodytype $ctype
			    dict set parm _body $body
			}
		    }
		}

		return $parm
	    }

	    #
	    # Extract individual parameters
	    # - parm: dictionary containing
	    #

	    proc keyval {parm lkv} {
		foreach kv $lkv {
		    if {[regexp {^([^=]+)=(.*)$} $kv foo key val]} then {
			set key [::ncgi::decode $key]
			set val [::ncgi::decode $val]
			dict lappend parm $key $val
		    }
		}
		return $parm
	    }

	    #
	    # Extract content-type from headers and returns
	    # a 2-element list: {<content-type> <charset>}
	    # Example : {application/x-www-form-urlencoded utf-8}
	    #

	    proc content-type {hdrs} {
		set h [dget $hdrs CONTENT_TYPE]
		set charset "utf-8"
		switch -regexp -matchvar m -- $h {
		    {^([^;]+)$} {
			set ctype [lindex $m 1]
		    }
		    {^([^;\s]+)\s*;\s*(.*)$} {
			set ctype [lindex $m 1]
			set parm [lindex $m 2]
			foreach p [split $parm ";"] {
			    lassign [split $p "="] k v
			    if {$k eq "charset"} then {
				set charset $v
			    }
			}
		    }
		    default {
			set ctype $h
		    }
		}
		return [list $ctype $charset]
	    }

	    #
	    # Parse cookies
	    # Returns a dictionary
	    #

	    proc parse-cookie {} {
		set cookie [dict create]
		set ck [get-header HTTP_COOKIE]
		foreach kv [split $ck ";"] {
		    if {[regexp {^\s*([^=]+)=(.*)} $kv foo k v]} then {
			dict set cookie $k $v
		    }
		}
		return $cookie
	    }

	    #
	    # Get a value from a dictionary, using a default value
	    # if key is not found.
	    #

	    proc dget {dict key {defval {}}} {
		if {[dict exists $dict $key]} then {
		    set v [dict get $dict $key]
		} else {
		    set v $defval
		}
		return $v
	    }
	}
    }
}