package cmd

import (
	"context"
	"fmt"
	"os"

	"dagger.io/dagger"
	"github.com/lionsdev/lionsctl/lionsctl"
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

		runOptions := lionsctl.PipelineOptions{
			SourceURL:   url,
			Branch:      branch,
			Profile:     profile,
			Define:      define,
			Environment: environment,
			Cluster:     cluster,
			Mails:       mails,
			JavaVersion: javaVersion,
		}

		err = lionsctl.Run(ctx, client, &runOptions)
		if err != nil {
			return err
		}

		return nil
	},
}

func init() {
	rootCmd.AddCommand(pipelineCmd)
	pipelineCmd.Flags().StringVarP(&url, "url", "u", "", "application git repository url: eg -u https://github.com/lionsdev/my-application")
	pipelineCmd.Flags().StringVarP(&branch, "branch", "b", lionsctl.GIT_DEFAULT_BRANCH, "git branch: eg: -b main ")
	pipelineCmd.Flags().StringVarP(&profile, "profile", "p", "", "define maven profile: eg: -p dev ")
	pipelineCmd.Flags().StringSliceVarP(&define, "define", "d", []string{}, "define maven properties: eg: -d quarkus.profile=dev ")
	pipelineCmd.Flags().Int16VarP(&javaVersion, "java-version", "j", 11, "la version du jdk 11 ou 17")
	pipelineCmd.Flags().StringVarP(&environment, "environment", "e", "development", "le nom de l'environment: eg -e development")
	pipelineCmd.Flags().StringVarP(&cluster, "cluster", "c", "k2", "k8s cluster k1 or k2")
	mails = pipelineCmd.Flags().StringSliceP("mails", "m", []string{}, "notifcations emails, eg: -m  'admin@dev.lions.dev,ops@dev.lions.dev' ")
	pipelineCmd.MarkFlagRequired("url")
	pipelineCmd.MarkFlagRequired("branch")
	pipelineCmd.MarkFlagRequired("environment")
	pipelineCmd.MarkFlagRequired("cluster")
}
