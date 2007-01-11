/*
 * $Id: textread.c,v 1.3 2007-01-10 16:49:53 pda Exp $
 */

#include "graph.h"

/*
 * Dynamic objects used only during text read
 */

MOBJ *mobjlist [NB_MOBJ] ;

MOBJ *vlistmobj ;

/******************************************************************************
Small memory allocation function
******************************************************************************/

void *my_malloc (size_t s)
{
    void *p ;

    p = malloc (s) ;
    if (p == NULL)
	error (1, "cannot malloc") ;
    memset (p, 0, s) ;

    return p ;
}

/******************************************************************************
Check an existing node and returns a pointer to it
******************************************************************************/

static struct node *check_node (char *name, char *context)
{
    struct node *node ;

    node = symtab_to_node (symtab_get (name)) ;
    if (node == NULL)
    {
	inconsistency ("Reference to a non-existant node '%s' (context '%s')",
						name, context) ;
	exit (1) ;
    }
    return node ;
}


/******************************************************************************
Link management
******************************************************************************/

struct link *create_link (char *name, char *n1, char *n2)
{
    struct link *l ;
    struct linklist *ll ;
    char *tab [2] ;
    int i ;

    l = mobj_alloc (linkmobj, 1) ;

    if (name != NULL)
	name = symtab_to_name (symtab_get (name)) ;
    l->name = name ;

    tab [0] = n1 ;
    tab [1] = n2 ;
    for (i = 0 ; i < 2 ; i++)
    {
	l->node [i] = check_node (tab [i], "link statement") ;

	ll = mobj_alloc (llistmobj, 1) ;
	ll->link = l ;
	ll->next = l->node [i]->linklist ;
	l->node [i]->linklist = ll ;
    }

    return l ;
}

/******************************************************************************
Attribute parsing
******************************************************************************/

struct attrtab
{
    char *attr ;
    struct attrvallist *first, *last ;
    struct attrtab *next ;
} ;

struct attrvallist 
{
    char *val ;
    struct attrvallist *next ;
} ;

static struct attrtab *attr_init (void)
{
    return NULL ;
}

static void attr_close (struct attrtab *at)
{
    while (at != NULL)
    {
	struct attrtab *t ;
	struct attrvallist *av ;

	t = at->next ;
	av = at->first ;
	while (av != NULL)
	{
	    struct attrvallist *tv ;

	    tv = av->next ;
	    free (av->val) ;
	    free (av) ;
	    av = tv ;
	}
	free (at->attr) ;
	free (at) ;
	at = t ;
    }
}

static struct attrtab *attr_get (struct attrtab *at, char *name)
{
    while (at != NULL)
    {
	if (strcmp (at->attr, name) == 0)
	    return at ;
	at = at->next ;
    }
    return NULL ;
}

static struct attrvallist *attr_get_vallist (struct attrtab *at, char *name)
{
    struct attrtab *a ;
    struct attrvallist *av ;

    a = attr_get (at, name) ;
    if (a == NULL)
	av = NULL ;
    else
	av = a->first ;

    return av ;
}

static char *attr_get_val (struct attrvallist *av)
{
    return av->val ;
}

/* insert a new attribute (without value) in attr list */
static struct attrtab *attr_append (struct attrtab **hd, char *name)
{
    struct attrtab *at ;

    at = my_malloc (sizeof *at) ;
    at->attr = my_malloc (strlen (name) + 1) ;
    strcpy (at->attr, name) ;
    at->first = at->last = NULL ;
    at->next = *hd ;
    *hd = at ;
    return at ;
}

static void attr_val_append (struct attrtab *at, char *val)
{
    struct attrvallist *av ;

    av = my_malloc (sizeof *av) ;
    av->val = my_malloc (strlen (val) + 1) ;
    strcpy (av->val, val) ;
    av->next = NULL ;
    if (at->last != NULL)
	at->last->next = av ;
    if (at->first == NULL)
	at->first = av ;
    at->last = av ;
}

/* nb of val for attr */
static int attr_get_nval (struct attrvallist *av)
{
    int n ; 

    n = 0 ;
    while (av != NULL)
    {
	n++ ;
	av = av->next ;
    }
    return n ;
}



static void parse_attr (char *tab [], int ntab, struct attrtab **hd)
{
    int i, j ;
    struct attrtab *at ;
    char val [MAXLINE], *p ;
    static struct
    {
	char *name ;			/* attribute name */
	int  nparam ;			/* number of parameters for this attr */
    } attrtypes [] =
    {
	{ "type", 1,	},
	{ "eq", 1,	},
	{ "name", 1,	},
	{ "desc", 1,	},
	{ "link", 1,	},
	{ "stat", 1,	},
	{ "encap", 1,	},
	{ "net", 1,	},
	{ "vlan", 1,	},
	{ "allow", 2,	},
	{ "addr", 1,	},
	{ "instance", 1,	},
	{ "model", 1,	},
	{ "snmp", 1,	},
    } ;


    while (ntab > 0)
    {
	for (i = 0 ; i < NTAB (attrtypes) ; i++)
	{
	    if (strcmp (tab [0], attrtypes [i].name) == 0)
	    {
		at = attr_get (*hd, tab [0]) ;
		if (at == NULL)
		    at = attr_append (hd, tab [0]) ;

		ntab-- ; tab++ ;

		if (ntab < attrtypes [i].nparam)
		{
		    inconsistency ("Not enough values for attribute '%s'", tab [0]) ;
		    exit (1) ;
		}

		for (j = 0 ; j < attrtypes [i].nparam ; j++)
		{
		    if (j == 0)
			p = val ;
		    else
			*p++ = ' ' ;

		    strcpy (p, tab [0]) ;
		    p += strlen (p) ;

		    ntab-- ; tab++ ;
		}

		attr_val_append (at, val) ;
		break ;
	    }
	}
	if (i >= NTAB (attrtypes))
	{
	    inconsistency ("Unrecognized keyword '%s'", tab [0]) ;
	    exit (1) ;
	}
    }
}

/******************************************************************************
Process net lists associated to L1 & L2 interfaces
******************************************************************************/

static void process_netlist (struct netlist **head, struct attrtab *attrtab)
{
    struct attrvallist *av ;
    struct netlist *nl ;

    *head = NULL ;

    av = attr_get_vallist (attrtab, "net") ;
    while (av != NULL)
    {
	char *addr ;
	struct network *n ;

	addr = attr_get_val (av) ;
	n = net_get_p (addr) ;

	/*
	 * First, look for the same network in our list, just in case
	 */

	for (nl = *head ; nl != NULL ; nl = nl->next)
	    if (ip_equal (&nl->net->addr, &n->addr))
		break ;

	/*
	 * If not found, insert it
	 */

	if (nl == NULL)
	{
	    nl = mobj_alloc (nlistmobj, 1) ;
	    nl->net = n ;
	    nl->next = *head ;
	    *head = nl ;
	}

	av = av->next ;
    }
}

/******************************************************************************
Build the initial graph
******************************************************************************/

static void process_L1 (struct attrtab *attrtab, struct node *n)
{
    char *ifname ;
    char *ifdesc ;
    char *link ;
    char *encap ;
    char *stat ;

    ifname = attr_get_val (attr_get_vallist (attrtab, "name")) ;
    n->u.l1.ifname = symtab_to_name (symtab_get (ifname)) ;

    ifdesc = attr_get_val (attr_get_vallist (attrtab, "desc")) ;
    ifdesc = symtab_to_name (symtab_get (ifdesc)) ;
    if (strcmp (ifdesc, "-") == 0) {
	ifdesc = NULL ;
    }
    n->u.l1.ifdesc = ifdesc ;

    link = attr_get_val (attr_get_vallist (attrtab, "link")) ;
    n->u.l1.link = symtab_to_name (symtab_get (link)) ;

    stat = attr_get_val (attr_get_vallist (attrtab, "stat")) ;
    stat = symtab_to_name (symtab_get (stat)) ;
    if (strcmp (stat, "-") == 0) {
	stat = NULL ;
    }
    n->u.l1.stat = stat ;

    encap = attr_get_val (attr_get_vallist (attrtab, "encap")) ;
    if (strcmp (encap, "trunk") == 0)
	n->u.l1.l1type = L1T_TRUNK ;
    else if (strcmp (encap, "ether") == 0)
	n->u.l1.l1type = L1T_ETHER ;
    else
    {
	inconsistency ("Invalid encap type (%s)", encap) ;
	exit (1) ;
    }
}

static void process_L2 (struct attrtab *attrtab, struct node *n)
{
    char *s ;
    vlan_t vlan ;
    char *stat ;

    s = attr_get_val (attr_get_vallist (attrtab, "vlan")) ;
    vlan = atoi (s) ;
    if (vlan < 0)
    {
	inconsistency ("Invalid vlan-id (%s)", s) ;
	exit (1) ;
    }
    n->u.l2.vlan = vlan ;

    stat = attr_get_val (attr_get_vallist (attrtab, "stat")) ;
    stat = symtab_to_name (symtab_get (stat)) ;
    if (strcmp (stat, "-") == 0) {
	stat = NULL ;
    }
    n->u.l2.stat = stat ;
}

static void process_L3 (struct attrtab *attrtab, struct node *n)
{
    char *addr ;
    int r ;

    addr = attr_get_val (attr_get_vallist (attrtab, "addr")) ;
    r = ip_pton (addr, &n->u.l3.addr) ;
    if (r == 0)
    {
	inconsistency ("Invalid address (%s)", addr) ;
	exit (1) ;
    }
}

static void process_bridge (struct attrtab *attrtab, struct node *n)
{
    /* nothing to do for bridges */
}

static void process_router (struct attrtab *attrtab, struct node *n)
{
    char *instance ;

    instance = attr_get_val (attr_get_vallist (attrtab, "instance")) ;
    n->u.router.name = symtab_to_name (symtab_get (instance)) ;
}

static void process_L2pat (struct attrtab *attrtab, struct node *n)
{
    struct attrvallist *av ;

    av = attr_get_vallist (attrtab, "allow") ;
    while (av != NULL)
    {
	vlan_t v1, v2 ;
	struct vlanlist *vl ;

	if (sscanf (attr_get_val (av), "%d %d", &v1, &v2) != 2)
	{
	    inconsistency ("Unrecognized vlan range (%s)", attr_get_val (av)) ;
	    exit (1) ;
	}

	vl = mobj_alloc (vlistmobj, 1) ;
	vl->min = v1 ;
	vl->max = v2 ;
	vl->next = n->u.l2pat.allowed ;
	n->u.l2pat.allowed = vl ;

	av = av->next ;
    }
}

static void process_brpat (struct attrtab *attrtab, struct node *n)
{
    /* nothing to do for bridge patterns */
}

struct attrcheck
{
    char *attr ;
    int minoccurr ;
    int maxoccurr ;
} ;

static int check_attr (struct attrtab *attrtab, struct attrcheck ac [])
{
    int i ;
    struct attrvallist *av ;
    int noc ;

    for (i = 0 ; ac [i].attr != NULL ; i++)
    {
	av = attr_get_vallist (attrtab, ac [i].attr) ;
	if (av == NULL)
	    noc = 0 ;
	else
	    noc = attr_get_nval (av) ;

	if (noc < ac [i].minoccurr || noc > ac [i].maxoccurr)
	{
	    inconsistency ("Invalid number (%d) of '%s' values (should be in [%d..%d])",
			noc,  ac [i].attr, ac [i].minoccurr, ac [i].maxoccurr) ;
	    return 0 ;
	}
    }

    /*
     * XXX : we should test that every attribute mentionned for this
     *		node is in the struct attrcheck array.
     */

    return 1 ;
}

static void process_eq (char *tab [0], int ntab)
{
    struct eq *eq ;
    char *eqname ;
    char *eqtype ;
    char *eqmodel ;
    char *eqsnmp ;
    struct attrtab *attrtab ;			/* head of attribute table */
    struct attrvallist *av ;
    static struct attrcheck eqattr [] = {
	{ "type", 1, 1},
	{ "model", 1, 1},
	{ "snmp", 1, 1},
	{ NULL, 0, 0}
    } ;


    if (ntab < 2)
    {
	inconsistency ("Eq declaration has not enough attributes") ;
	exit (1) ;
    }

    eqname = tab [1] ;
    tab += 2 ;
    ntab -= 2 ;

    /*
     * Locate proper equipement
     */

    eq = eq_get (eqname, 0) ;

    /*
     * Parse all attributes
     */

    attrtab = attr_init () ;
    parse_attr (tab, ntab, &attrtab) ;

    if (! check_attr (attrtab, eqattr))
    {
	inconsistency ("Incorrect eq attribute list") ;
	exit (1) ;
    }

    av = attr_get_vallist (attrtab, "type") ;
    if (av != NULL)
	eqtype = attr_get_val (av) ;
    else
    {
	inconsistency ("Should not happen : 'eq %s' without type", eqname) ;
	exit (1) ;
    }

    av = attr_get_vallist (attrtab, "model") ;
    if (av != NULL)
	eqmodel = attr_get_val (av) ;
    else
    {
	inconsistency ("Should not happen : 'eq %s' without model", eqname) ;
	exit (1) ;
    }

    av = attr_get_vallist (attrtab, "snmp") ;
    if (av != NULL)
	eqsnmp = attr_get_val (av) ;
    else
    {
	inconsistency ("Should not happen : 'eq %s' without SNMP community", eqname) ;
	exit (1) ;
    }

    eq->type = symtab_to_name (symtab_get (eqtype)) ;
    eq->model = symtab_to_name (symtab_get (eqmodel)) ;
    if (strcmp (eqsnmp, "-") == 0)
	eq->snmp = NULL ;
    else eq->snmp = symtab_to_name (symtab_get (eqsnmp)) ;

    attr_close (attrtab) ;
}


#define MAXKWBYTYPE 10

static void process_node (char *tab [], int ntab)
{
    int i ;
    struct node *n ;
    char *nodename ;
    char *nodetype ;
    struct eq *eq ;
    struct attrtab *attrtab ;			/* head of attribute table */
    struct attrvallist *av ;
    static struct
    {
	char *type ;
	enum nodetype nodetype ;
	void (*fct) (struct attrtab *, struct node *) ;
	struct attrcheck attr [MAXKWBYTYPE] ;
    } attrbytype [] =
    {
	{ "L1" , NT_L1,     process_L1, {
			{ "type", 1, 1 },
		        { "eq", 1, 1 },
		        { "name", 1, 1 },
		        { "desc", 1, 1 },
		        { "link", 1, 1 },
		        { "stat", 1, 1 },
		        { "encap", 1, 1 },
			{ "net", 0, 1000000 },
		        { NULL, 0 },
	       },
	},
	{ "L2" , NT_L2,     process_L2, {
			{ "type", 1, 1 },
			{ "eq", 1, 1 },
			{ "vlan", 1, 1 },
		        { "stat", 1, 1 },
			{ NULL, 0 },
		},
	},
	{ "L3" , NT_L3,     process_L3, {
			{ "type", 1, 1 },
			{ "eq", 1, 1 },
			{ "addr", 1, 1 },
			{ NULL, 0 },
		},
	},
	{ "router" , NT_ROUTER, process_router, {
			{ "type", 1, 1 },
			{ "eq", 1, 1 },
			{ "instance", 1, 1 },
			{ NULL, 0 },
		    },
	},
	{ "bridge" , NT_BRIDGE, process_bridge, {
			{ "type", 1, 1 },
			{ "eq", 1, 1 },
			{ NULL, 0 },
		    },
	},
	{ "L2pat" , NT_L2PAT,  process_L2pat, {
			{ "type", 1, 1 },
			{ "eq", 1, 1 },
			{ "allow", 0, 1000000 },
			{ NULL, 0 },
		    },
	},
	{ "brpat" , NT_BRPAT,  process_brpat, {
			{ "type", 1, 1 },
			{ "eq", 1, 1 },
			{ NULL, 0 },
		    },
	},
    } ;


    if (ntab < 2)
    {
	inconsistency ("Node has not enough attributes") ;
	exit (1) ;
    }

    nodename = tab [1] ;
    tab += 2 ;
    ntab -= 2 ;

    /*
     * Parse all attributes
     */

    attrtab = attr_init () ;
    parse_attr (tab, ntab, &attrtab) ;

    av = attr_get_vallist (attrtab, "type") ;
    if (av == NULL)
    {
	inconsistency ("Node '%s' has no type", nodename) ;
	exit (1) ;
    }
    nodetype = attr_get_val (av) ;

    /*
     * Specific analysis given the nodetype
     */

    for (i = 0 ; i < NTAB (attrbytype) ; i++)
    {
	if (strcmp (nodetype, attrbytype [i].type) == 0)
	{
	    if (! check_attr (attrtab, attrbytype [i].attr))
	    {
		inconsistency ("Incorrect node attribute list") ;
		exit (1) ;
	    }

	    eq = eq_get (attr_get_val (attr_get_vallist (attrtab, "eq")), 0) ;

	    n = create_node (nodename, eq,  attrbytype [i].nodetype) ;
	    (*attrbytype [i].fct) (attrtab, n) ;
	    break ;
	}
    }
    if (i >= NTAB (attrbytype))
    {
	inconsistency ("Unrecognized type '%s' for node '%s'", nodetype, nodename) ;
	exit (1) ;
    }

    attr_close (attrtab) ;
}

static void process_link (char *tab [], int ntab)
{
    char *linkname ;
    char *n1, *n2 ;
    struct attrtab *attrtab ;			/* head of attribute table */
    struct attrvallist *av ;
    static struct attrcheck linkattr [] = {
	{ "name", 0, 1},
	{ NULL, 0, 0}
    } ;

    if (ntab < 3)
    {
	inconsistency ("Link has not enough data") ;
	exit (1) ;
    }

    n1 = tab [1] ;
    n2 = tab [2] ;
    tab += 3 ;
    ntab -= 3 ;

    /*
     * Parse all attributes
     */

    attrtab = attr_init () ;
    parse_attr (tab, ntab, &attrtab) ;

    if (! check_attr (attrtab, linkattr))
    {
	inconsistency ("Incorrect link attribute list") ;
	exit (1) ;
    }

    av = attr_get_vallist (attrtab, "name") ;
    if (av != NULL)
	linkname = attr_get_val (av) ;
    else linkname = NULL ;

    (void) create_link (linkname, n1, n2) ;
}

struct route *process_static_routes (char *tab [], int ntab)
{
    struct route *head, *r ;

    if (ntab % 2 != 0)
    {
	inconsistency ("Odd number of route entries") ;
	exit (1) ;
    }
    head = NULL ;
    while (ntab > 0)
    {
	r = mobj_alloc (routemobj, 1) ;

	if (! ip_pton (tab [0], &r->net))
	    inconsistency ("Route '%s'->'%s' has a bad address", tab [0], tab [1]) ;
	if (! ip_pton (tab [1], &r->gw))
	    inconsistency ("Route '%s'->'%s' has a bad gateway", tab [0], tab [1]) ;

	r->next = head ;
	head = r ;

	tab += 2 ;
	ntab -= 2 ;
    }
    return head ;
}

static void process_rnet (char *tab [], int ntab)
{
    struct rnet *n ;
    struct network *net ;
    char *vrrpaddr ;

    if (ntab < 8)
    {
	inconsistency ("Routed network has not enough data") ;
	exit (1) ;
    }

    n = mobj_alloc (rnetmobj, 1) ;

    net = net_get_p (tab [1]) ;
    if (net == NULL)
	error (0, "Cannot find a slot for net") ;
    n->net = net ;

    n->router = check_node (tab [2], tab [1]) ;
    n->l3     = check_node (tab [3], tab [1]) ;
    n->l2     = check_node (tab [4], tab [1]) ;
    n->l1     = check_node (tab [5], tab [1]) ;

    vrrpaddr = tab [6] ;
    if (strcmp (vrrpaddr, "-") == 0)
	vrrpaddr = "0.0.0.0/0" ;
    if (! ip_pton (vrrpaddr, &n->vrrpaddr))
	inconsistency ("Routed network '%s' has a bad VRRP address (%s)",
					tab [1], vrrpaddr) ;
    n->vrrpprio = atoi (tab [7]) ;

    tab += 8 ;
    ntab -= 8 ;
    n->routelist = process_static_routes (tab, ntab) ;

    n->next = mobj_head (rnetmobj) ;
    mobj_sethead (rnetmobj, n) ;
}

static void process_vlan (char *tab [], int ntab)
{
    int vlanid ;
    char *id, *desc ;
    struct attrtab *attrtab ;			/* head of attribute table */
    struct attrvallist *av ;
    static struct attrcheck vlanattr [] = {
	{ "desc", 1, 1},
	{ "net",  0, 100000},
	{ NULL, 0, 0}
    } ;
    struct vlan *tabvlan ;

    if (ntab < 2)
    {
	inconsistency ("Vlan declaration has not enough attributes") ;
	exit (1) ;
    }

    tabvlan = mobj_data (vlanmobj) ;
    vlanid = 0 ;

    id = tab [1] ;
    if (sscanf (id, "%d", &vlanid) != 1 || vlanid  >= MAXVLAN)
	inconsistency ("Incorrect vlan-id ('%s')", id) ;

    tab += 2 ;
    ntab -= 2 ;

    /*
     * Parse all attributes
     */

    attrtab = attr_init () ;
    parse_attr (tab, ntab, &attrtab) ;

    if (! check_attr (attrtab, vlanattr))
    {
	inconsistency ("Incorrect vlan attribute list") ;
	exit (1) ;
    }

    av = attr_get_vallist (attrtab, "desc") ;
    if (av != NULL)
	desc = symtab_to_name (symtab_get (attr_get_val (av))) ;
    else desc = NULL ;

    tabvlan [vlanid].name = desc ;

    process_netlist (&tabvlan [vlanid].netlist, attrtab) ;

    attr_close (attrtab) ;
}

/******************************************************************************
The real function of this file
******************************************************************************/

void text_read (FILE *fpin)
{
    char orgline [MAXLINE] ;
    char line [MAXLINE] ;
    MOBJ *args ; char **argv ;
    char *p ;
    char *tok ;
    int n ;

    hashmobj  = mobj_init (sizeof (struct symtab *), MOBJ_CONST) ;
    symtab_init () ;

    symmobj   = mobj_init (sizeof (struct symtab  ), MOBJ_MALLOC) ;
    strmobj   = mobj_init (sizeof (char           ), MOBJ_MALLOC) ;
    nodemobj  = mobj_init (sizeof (struct node    ), MOBJ_MALLOC) ;
    linkmobj  = mobj_init (sizeof (struct link    ), MOBJ_MALLOC) ;
    llistmobj = mobj_init (sizeof (struct linklist), MOBJ_MALLOC) ;
    eqmobj    = mobj_init (sizeof (struct eq      ), MOBJ_MALLOC) ;
    netmobj   = mobj_init (sizeof (struct network ), MOBJ_MALLOC) ;
    nlistmobj = mobj_init (sizeof (struct netlist ), MOBJ_MALLOC) ;
    rnetmobj  = mobj_init (sizeof (struct rnet    ), MOBJ_MALLOC) ;
    routemobj = mobj_init (sizeof (struct route   ), MOBJ_MALLOC) ;
    vlistmobj = mobj_init (sizeof (struct vlanlist), MOBJ_MALLOC) ;

    vlanmobj  = mobj_init (sizeof (struct vlan    ), MOBJ_CONST) ;
    mobj_alloc (vlanmobj, MAXVLAN) ;

    args = mobj_init (sizeof (char *), MOBJ_REALLOC) ;

    lineno = 0 ;
    while (fgets (line, sizeof line, fpin) != NULL)
    {
	lineno++ ;
	strcpy (orgline, line) ;	/* save a copy for later use */

	p = strchr (line, '\n') ;
	if (p != NULL)
	    *p = '\0' ;

	p = strchr (line, '#') ;	/* remove comments */
	if (p != NULL)
	    *p = '\0' ;

	/*
	 * Very simplistic syntax analysis
	 */

	p = line ;

	mobj_empty (args) ;
	(void) mobj_alloc (args, 1) ;	/* last NULL entry */

	n = 0 ;
	argv = mobj_data (args) ;
	argv [n] = NULL ;

	while ((tok = strsep (&p, " \t")) != NULL)
	    if (tok [0] != '\0')
	    {
		(void) mobj_alloc (args, 1) ;
		argv = mobj_data (args) ;
		argv [n++] = tok ;
		argv [n] = NULL ;
	    }

	argv = mobj_data (args) ;

	if (argv [0] != NULL)
	{
	    if (strcmp (argv [0], "eq") == 0)
		process_eq (argv, n) ;
	    else if (strcmp (argv [0], "node") == 0)
		process_node (argv, n) ;
	    else if (strcmp (argv [0], "link") == 0)
		process_link (argv, n) ;
	    else if (strcmp (argv [0], "rnet") == 0)
		process_rnet (argv, n) ;
	    else if (strcmp (argv [0], "vlan") == 0)
		process_vlan (argv, n) ;
	    else
	    {
		inconsistency ("Unknown directive '%s'", argv [0]) ;
		exit (1) ;
	    }
	}
	else
	    ;				/* ignore it */
    }
    lineno = -1 ;

    mobj_close (args) ;
}