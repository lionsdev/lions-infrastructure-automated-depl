package sigctlv2

import (
	"bytes"
	"fmt"
	"log"
	"net/http"
	"net/url"
	"os/user"
	"strings"

	"github.com/spf13/viper"
)

var (
	logBuffer bytes.Buffer
	sigLogger = log.New(&logBuffer, "--sigctl-- ", log.LstdFlags)
)

func SigInfo(msg string) {
	sigLogger.Printf(msg)
	fmt.Print(&logBuffer)

}

func UserHome() string {

	currentUser, err := user.Current()
	if err != nil {
		log.Fatal(err)
	}

	return currentUser.HomeDir

}

func AppName(gitUrl string) (string, error) {
	u, err := url.Parse(gitUrl)
	if err != nil {
		return "", err
	}

	path := u.Path
	parts := strings.Split(path, "/")
	name := parts[len(parts)-1]

	//fmt.Printf("--- Application name part: %s", name)

	return name, err
}

func request(url, verb string, body []byte) error {

	log.Printf("--- POST URL: %s", url)

	bodyReader := bytes.NewReader(body)
	req, err := http.NewRequest(verb, url, bodyReader)
	if err != nil {
		return err
	}

	req.Header.Set("accept", "application/json")
	req.Header.Set("Authorization", "token "+viper.GetString("GIT.ACCESS_TOKENS"))
	req.Header.Set("Content-Type", "application/json")

	res, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}

	buff := new(bytes.Buffer)
	buff.ReadFrom(res.Body)

	log.Println(buff.String())

	res.Body.Close()

	return nil

}
