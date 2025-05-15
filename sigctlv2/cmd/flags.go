package cmd

var (
	name          string    //application name
	url           string    //application git repository url
	branch        string    //application git branch
	source        string    //application source code directory
	digest        string    //application git repo branch digest
	profile       string    //maven profile
	define        []string  //define maven properties
	dockerContext string    //docker context
	tag           string    //docker image tag
	cluster       string    //kubernetes cluster to use
	environment   string    //kubernets environment in cluster
	ingress       bool      //add ingress or not
	volume        bool      //add volume or not
	configURL     string    //configuration git repo url
	configBranch  string    //configuration git repo branch
	javaVersion   int16     //Java version
	mails         *[]string //notification emails addr
)
