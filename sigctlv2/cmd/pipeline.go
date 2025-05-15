/*
Copyright © 2023 NAME HERE <EMAIL ADDRESS>
*/
package cmd

import (
	"context"
	"fmt"
	"os"

	"dagger.io/dagger"
	"github.com/kouame-florent/sigctlv2/sigctlv2"
	"github.com/spf13/cobra"
)

// pipelineCmd represents the pipeline command
var pipelineCmd = &cobra.Command{
	Use:   "pipeline",
	Short: "Effectue toutes les étapes pour deployer l'application sur kubernetes",
	Long: `La commande deploy réalise les taches suivantes:
	- cloner l'application
	- tester et construire l'executable
	- contruire l'image docker 
	- tagger l'image avec le hash du commit de la branche sélectionnée
	- deployer l'image docker dans le registre
	- mettre à jour le tag de l'image dans les fichiers de configuration de deploiement
	- deployer l'application dans l'environnement sélectionné
	- envoyer les notifications aux emails choisis
	`,
	RunE: func(cmd *cobra.Command, args []string) error {
		fmt.Println("deploy called")

		ctx := context.Background()

		client, err := dagger.Connect(ctx, dagger.WithLogOutput(os.Stdout))
		if err != nil {
			return err
		}

		defer client.Close()

		runOptions := sigctlv2.PipelineOptions{
			SourceURL:   url,
			Branch:      branch,
			Profile:     profile,
			Define:      define,
			Environment: environment,
			Cluster:     cluster,
			Mails:       mails,
			JavaVersion: javaVersion,
		}

		err = sigctlv2.Run(ctx, client, &runOptions)
		if err != nil {
			return err
		}

		return nil
	},
}

func init() {
	rootCmd.AddCommand(pipelineCmd)
	pipelineCmd.Flags().StringVarP(&url, "url", "u", "", "application git repository url: eg -u http://10.3.4.18:3001/florent/mic-greeting")
	pipelineCmd.Flags().StringVarP(&branch, "branch", "b", sigctlv2.GIT_DEFAULT_BRANCH, "git branch: eg: -b preproduction ")
	pipelineCmd.Flags().StringVarP(&profile, "profile", "p", "", "define maven profile: eg: -p dev ")
	pipelineCmd.Flags().StringSliceVarP(&define, "define", "d", []string{}, "define maven properties: eg: -d quarkus.profile=dev ")
	pipelineCmd.Flags().Int16VarP(&javaVersion, "java-version", "j", 11, "la version du jdk 11 ou 17")
	pipelineCmd.Flags().StringVarP(&environment, "environment", "e", "dev", "le nom de l'environment: eg -e dev")
	pipelineCmd.Flags().StringVarP(&cluster, "cluster", "c", "k2", "k8s cluster k1 or k2")
	mails = pipelineCmd.Flags().StringSliceP("mails", "m", []string{}, "notifcations emails, eg: -m  'foo@gmail.com,bar@gmail.com' ")
	pipelineCmd.MarkFlagRequired("url")
	pipelineCmd.MarkFlagRequired("branch")
	pipelineCmd.MarkFlagRequired("environment")
	pipelineCmd.MarkFlagRequired("cluster")

	// Here you will define your flags and configuration settings.

	// Cobra supports Persistent Flags which will work for this command
	// and all subcommands, e.g.:
	// pipelineCmd.PersistentFlags().String("foo", "", "A help for foo")

	// Cobra supports local flags which will only run when this command
	// is called directly, e.g.:
	// pipelineCmd.Flags().BoolP("toggle", "t", false, "Help message for toggle")
}
