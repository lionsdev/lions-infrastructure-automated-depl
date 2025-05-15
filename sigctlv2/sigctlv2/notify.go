package sigctlv2

import (
	"bytes"
	"context"
	"encoding/json"
	"log"
	"net/http"

	"dagger.io/dagger"
	"github.com/spf13/viper"
)

type NotifyOptions struct {
	AppName     string
	Digest      string //commit hash from git step
	Recipients  *[]string
	Environment string
}

type email struct {
	From          string
	To            string
	Subject       string
	TextBody      string
	HtmlBody      string
	MessageStream string
}

func Notify(ctx context.Context, client *dagger.Client, opts NotifyOptions) error {

	for _, e := range *opts.Recipients {
		log.Printf("---SENDING MAIL TO: %s\n", e)

		htmlbody := "<b>Microservice:</b> " + opts.AppName + "<br>" + "<b>Environnement:</b> " + opts.Environment + "<br>" + "<b>Tag:</b> " + opts.Digest

		msg := email{
			From:          viper.GetString("NOTIFICATION.FROM_URL"),
			To:            e,
			Subject:       "cicd pipeline",
			HtmlBody:      htmlbody,
			MessageStream: "outbound",
		}

		data, err := json.Marshal(msg)
		if err != nil {
			return err
		}

		body := bytes.NewBuffer(data)

		client := &http.Client{}
		req, err := http.NewRequest("POST", viper.GetString("NOTIFICATION.SMTP_URL"), body)
		if err != nil {
			return err

		}
		req.Header.Add("Content-Type", "application/json")
		req.Header.Add("X-Postmark-Server-Token", viper.GetString("NOTIFICATION.SERVER_TOKEN"))

		resp, err := client.Do(req)
		if err != nil {
			return err

		}

		defer resp.Body.Close()

	}

	return nil

}
