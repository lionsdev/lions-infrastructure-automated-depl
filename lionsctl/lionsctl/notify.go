package lionsctl

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"log"
	"net/http"

	"dagger.io/dagger"
	"github.com/spf13/viper"
)

type NotifyOptions struct {
	AppName     string
	Digest      string
	Environment string
	Recipients  *[]string
}

type EmailRequest struct {
	From     string   `json:"From"`
	To       []string `json:"To"`
	Subject  string   `json:"Subject"`
	HtmlBody string   `json:"HtmlBody"`
	TextBody string   `json:"TextBody"`
}

func Notify(ctx context.Context, client *dagger.Client, opts NotifyOptions) error {

	fmt.Println("--- NOTIFY")

	if opts.Recipients == nil || len(*opts.Recipients) == 0 {
		log.Println("--- NO RECIPIENTS")
		return nil
	}

	log.Printf("--- RECIPIENTS: %v", *opts.Recipients)

	subject := fmt.Sprintf("Déploiement de %s en %s", opts.AppName, opts.Environment)
	htmlBody := fmt.Sprintf("<h1>Déploiement de %s</h1><p>L'application %s a été déployée en %s avec le tag %s</p>", opts.AppName, opts.AppName, opts.Environment, opts.Digest)
	textBody := fmt.Sprintf("Déploiement de %s\nL'application %s a été déployée en %s avec le tag %s", opts.AppName, opts.AppName, opts.Environment, opts.Digest)

	emailReq := EmailRequest{
		From:     viper.GetString("NOTIFICATION.FROM_URL"),
		To:       *opts.Recipients,
		Subject:  subject,
		HtmlBody: htmlBody,
		TextBody: textBody,
	}

	emailReqJson, err := json.Marshal(emailReq)
	if err != nil {
		return err
	}

	req, err := http.NewRequest("POST", viper.GetString("NOTIFICATION.SMTP_URL"), bytes.NewBuffer(emailReqJson))
	if err != nil {
		return err
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Postmark-Server-Token", viper.GetString("NOTIFICATION.SERVER_TOKEN"))

	client2 := &http.Client{}
	resp, err := client2.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	log.Printf("--- RESPONSE STATUS: %s", resp.Status)

	respBody, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		return err
	}

	log.Printf("--- RESPONSE BODY: %s", string(respBody))

	if resp.StatusCode >= 400 {
		return fmt.Errorf("notification failed with status: %s", resp.Status)
	}

	return nil
}