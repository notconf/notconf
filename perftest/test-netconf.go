package main

import (
	"context"
	"encoding/xml"
	"flag"
	"fmt"
	"log"
	"math"
	"os"
	"time"

	"github.com/nemith/netconf"
	ncssh "github.com/nemith/netconf/transport/ssh"
	"golang.org/x/crypto/ssh"
)

// arrayNamespaces is a helper type to allow multiple namespace flags
type arrayNamespaces []string

func (i *arrayNamespaces) String() string {
	return fmt.Sprintf("%v", *i)
}

func (i *arrayNamespaces) Set(value string) error {
	*i = append(*i, value)
	return nil
}

var namespaces arrayNamespaces

var (
	host          = flag.String("host", "localhost", "Hostname")
	port          = flag.Int("port", 830, "Port")
	username      = flag.String("username", "admin", "Username")
	password      = flag.String("password", "admin", "Password")
	n             = flag.Int("n", 10, "Number of times to repeat the request")
	verbose       = flag.Bool("v", false, "Verbose")
	getData       = flag.Bool("get-data", false, "Use <get-data> instead of <get-config>")
	datastore     = flag.String("datastore", "running", "Datastore")
	filterXpath   = flag.String("filter-xpath", "", "Filter XPath")
	filterSubtree = flag.String("filter-subtree", "", "Filter Subtree")
	rawRpcFile    = flag.String("raw-rpc", "", "Raw RPC file")
)

// OnlineVariance computes the sample variance incrementally using the Welford's algorithm
type OnlineVariance struct {
	ddof, n  int
	mean, M2 float64
}

func NewOnlineVariance(ddof int) *OnlineVariance {
	return &OnlineVariance{ddof: ddof}
}

func (ov *OnlineVariance) Include(datum float64) {
	ov.n++
	delta := datum - ov.mean
	ov.mean += delta / float64(ov.n)
	ov.M2 += delta * (datum - ov.mean)
}

func (ov *OnlineVariance) Variance() float64 {
	return ov.M2 / float64(ov.n-ov.ddof)
}

func (ov *OnlineVariance) Std() float64 {
	return math.Sqrt(ov.Variance())
}

func BuildConfig(username string, password string) *ssh.ClientConfig {
	config := &ssh.ClientConfig{
		User: username,
		Auth: []ssh.AuthMethod{
			ssh.Password(password),
		},
		HostKeyCallback: ssh.InsecureIgnoreHostKey(),
	}
	return config
}

type GetDataReply struct {
	XMLName xml.Name `xml:"data"`
	Reply   string   `xml:",innerxml"`
}

// GetData is a helper function to send a <get-data> request to the server
func GetData(session *netconf.Session, datastore string, filterXpath string, filterSubtree string) (*string, error) {
	request := "<get-data xmlns='urn:ietf:params:xml:ns:yang:ietf-netconf-nmda'>"
	if datastore != "" {
		request += fmt.Sprintf("<datastore xmlns:ds='urn:ietf:params:xml:ns:yang:ietf-datastores'>ds:%s</datastore>", datastore)
	}
	if filterXpath != "" {
		extraNamespaces := ""
		for _, ns := range namespaces {
			extraNamespaces += fmt.Sprintf(" xmlns:%s", ns)
		}
		request += fmt.Sprintf("<xpath-filter%s>%s</xpath-filter>", extraNamespaces, filterXpath)
	}
	if filterSubtree != "" {
		request += fmt.Sprintf("<subtree-filter>%s</subtree-filter>", filterSubtree)
	}
	request += "</get-data>"
	var reply GetDataReply
	if err := session.Call(context.Background(), request, &reply); err != nil {
		return nil, err
	}
	return &reply.Reply, nil
}

func main() {
	flag.Var(&namespaces, "namespace", "Namespace to use in the request (can be used multiple times)")
	flag.Parse()

	if *getData {
		if *filterXpath != "" && *filterSubtree != "" {
			log.Fatalf("only one of filter-xpath and filter-subtree can be used")
		}
	} else if *filterXpath != "" || *filterSubtree != "" {
		log.Fatalf("filters can only be used with <get-data>")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	sshAddr := fmt.Sprintf("%s:%d", *host, *port)
	transport, err := ncssh.Dial(ctx, "tcp", *&sshAddr, BuildConfig(*username, *password))
	if err != nil {
		panic(err)
	}
	defer transport.Close()

	session, err := netconf.Open(transport)
	if err != nil {
		panic(err)
	}

	// timeout for the call itself.
	ctx, cancel = context.WithTimeout(ctx, 5*time.Second)
	defer cancel()

	var getter func() (*string, error)

	if *rawRpcFile != "" {
		rawRpc, err := os.ReadFile(*rawRpcFile)
		if err != nil {
			log.Fatalf("failed to read raw-rpc file: %v", err)
		}
		getter = func() (*string, error) {
			var reply GetDataReply
			if err := session.Call(ctx, rawRpc, &reply); err != nil {
				return nil, err
			}
			return &reply.Reply, nil
		}
	} else if *getData {
		getter = func() (*string, error) {
			return GetData(session, *datastore, *filterXpath, *filterSubtree)
		}
	} else {
		getter = func() (*string, error) {
			deviceConfig, err := session.GetConfig(ctx, "running")
			if err != nil {
				return nil, err
			}
			dc := string(deviceConfig)
			return &dc, nil
		}
	}

	var ov = NewOnlineVariance(1)

	// Repeat the request a few times
	for i := 0; i < *n; i++ {
		// Store the start time in nanoseconds
		start := time.Now().UnixNano()

		response, err := getter()
		if err != nil {
			log.Fatalf("failed to get data: %v", err)
		}

		end := time.Now().UnixNano()
		ov.Include(float64(end - start))

		if *verbose {
			log.Printf("response:\n%s\n", *response)
		}
	}

	if err := session.Close(context.Background()); err != nil {
		log.Print(err)
	}

	var unit = "µ"
	var scale = 1000.0
	if ov.mean >= 1000 {
		unit = "m"
		scale = 1000000.0
	}
	fmt.Printf("--- netopeer %d: mean=%.6f %ss σ=%.6f %ss\n", *n, ov.mean/scale, unit, ov.Std()/scale, unit)
}
