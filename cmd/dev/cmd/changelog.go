// Package cmd provides command implementations for the dev tool.
package cmd

import (
	"bufio"
	"fmt"
	"log/slog"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/spf13/cobra"
)

func ChangelogCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "changelog",
		Short: "Manage changelog generation and tooling",
		Long: `Manage changelog generation using git-chglog based on conventional commits.

The changelog is generated from git commit history following the Conventional
Commits specification. Commits should follow the format:
  <type>[optional scope]: <description>

Supported types: feat, fix, docs, refactor, test, perf, build, ci, chore`,
	}

	cmd.AddCommand(changelogInitCmd())
	cmd.AddCommand(changelogGenerateCmd())

	return cmd
}

func changelogInitCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "init",
		Short: "Initialize changelog tooling (install git-chglog and setup git hooks)",
		Long: `Initialize changelog tooling for the project.

This command will:
  1. Install git-chglog if not already installed
  2. Verify .chglog configuration files exist
  3. Setup git commit-msg hook for commit message validation

The git hook will validate that commit messages follow the Conventional
Commits format before allowing commits.`,
		RunE: func(cmd *cobra.Command, args []string) error {
			slog.Info("setting up changelog tooling for RackMonitor")
			fmt.Println()

			// Check if we're in a git repository
			if _, err := os.Stat(".git"); os.IsNotExist(err) {
				slog.Error("not in a git repository")
				slog.Info("please run this command from the repository root")
				return fmt.Errorf("not in a git repository")
			}

			// Install git-chglog
			if _, err := exec.LookPath("git-chglog"); err != nil {
				slog.Info("installing git-chglog...")
				goInstall := exec.Command("go", "install", "github.com/git-chglog/git-chglog/cmd/git-chglog@latest")
				goInstall.Stdout = os.Stdout
				goInstall.Stderr = os.Stderr

				if err := goInstall.Run(); err != nil {
					return fmt.Errorf("failed to install git-chglog: %w", err)
				}

				// Verify it's now available
				if _, err := exec.LookPath("git-chglog"); err != nil {
					slog.Warn("git-chglog installed but not in PATH")
					slog.Info("make sure GOPATH/bin is in your PATH")
					slog.Info("add this to your shell profile:")
					gopath, err := exec.Command("go", "env", "GOPATH").Output()
					if err == nil {
						slog.Info(fmt.Sprintf("  export PATH=$PATH:%s/bin", strings.TrimSpace(string(gopath))))
					} else {
						slog.Info("  export PATH=$PATH:$(go env GOPATH)/bin")
					}
				} else {
					slog.Info("git-chglog installed successfully")
				}
			} else {
				slog.Info("git-chglog already installed")
			}

			fmt.Println()

			// Verify configuration files exist
			if _, err := os.Stat(".chglog/config.yml"); os.IsNotExist(err) {
				slog.Error(".chglog/config.yml not found")
				slog.Info("configuration files should already exist in the repository")
				return fmt.Errorf(".chglog/config.yml not found")
			}

			if _, err := os.Stat(".chglog/CHANGELOG.tpl.md"); os.IsNotExist(err) {
				slog.Error(".chglog/CHANGELOG.tpl.md not found")
				slog.Info("template file should already exist in the repository")
				return fmt.Errorf(".chglog/CHANGELOG.tpl.md not found")
			}

			slog.Info("git-chglog configuration files found")
			fmt.Println()

			// Setup git hook for commit message validation
			hookPath := ".git/hooks/commit-msg"
			if _, err := os.Stat(hookPath); err == nil {
				slog.Warn("git commit-msg hook already exists")
				fmt.Print("do you want to overwrite it? (y/N): ")
				reader := bufio.NewReader(os.Stdin)
				response, err := reader.ReadString('\n')
				if err != nil {
					return fmt.Errorf("failed to read user input: %w", err)
				}
				response = strings.TrimSpace(strings.ToLower(response))
				if response != "y" && response != "yes" {
					slog.Info("skipping git hook setup")
					return nil
				}
			}

			slog.Info("setting up git commit-msg hook...")

			hookContent := `#!/bin/bash
# Validate commit message format (Conventional Commits)

commit_msg=$(cat "$1")

# Allow merge commits
if echo "$commit_msg" | grep -qE "^Merge "; then
    exit 0
fi

# Allow revert commits
if echo "$commit_msg" | grep -qE "^Revert "; then
    exit 0
fi

# Check for conventional commit format
if ! echo "$commit_msg" | grep -qE "^(feat|fix|docs|refactor|test|perf|build|ci|chore)(\(.+\))?:.+"; then
    echo ""
    echo "❌ Commit message does not follow Conventional Commits format"
    echo ""
    echo "Format: <type>[optional scope]: <description>"
    echo ""
    echo "Types:"
    echo "  feat     - New features"
    echo "  fix      - Bug fixes"
    echo "  docs     - Documentation changes"
    echo "  refactor - Code refactoring"
    echo "  test     - Test additions/changes"
    echo "  perf     - Performance improvements"
    echo "  build    - Build system changes"
    echo "  ci       - CI/CD changes"
    echo "  chore    - Maintenance tasks"
    echo ""
    echo "Examples:"
    echo "  feat(sensor): add temperature threshold validation"
    echo "  fix(api): correct response format for alerts endpoint"
    echo "  docs: update README with build instructions"
    echo ""
    exit 1
fi

echo "✅ Commit message format valid"
`

			// Ensure .git/hooks directory exists
			if err := os.MkdirAll(filepath.Dir(hookPath), 0755); err != nil {
				return fmt.Errorf("failed to create hooks directory: %w", err)
			}

			if err := os.WriteFile(hookPath, []byte(hookContent), 0755); err != nil {
				return fmt.Errorf("failed to write git hook: %w", err)
			}

			slog.Info("git commit-msg hook installed")

			fmt.Println()
			slog.Info("changelog tooling setup complete!")
			fmt.Println()
			slog.Info("next steps:")
			slog.Info("  1. Start following Conventional Commits format for your commit messages")
			slog.Info("  2. Generate changelog with: ./dev changelog generate")
			slog.Info("  3. Or use Makefile: make changelog")
			fmt.Println()
			slog.Info("examples:")
			slog.Info("  # Generate full changelog")
			slog.Info("  ./dev changelog generate")
			fmt.Println()
			slog.Info("  # Generate changelog for next version")
			slog.Info("  ./dev changelog generate --next v1.2.0")
			slog.Info("  # Or interactively:")
			slog.Info("  make changelog-next")
			fmt.Println()
			slog.Info("  # Validate commits before pushing")
			slog.Info("  make validate-commits")
			fmt.Println()
			slog.Info("for more information, see:")
			slog.Info("  - Conventional Commits: https://www.conventionalcommits.org/")
			slog.Info("  - git-chglog: https://github.com/git-chglog/git-chglog")
			fmt.Println()

			return nil
		},
	}

	return cmd
}

func changelogGenerateCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "generate",
		Short: "Generate or update CHANGELOG.md from git history",
		Long: `Generate CHANGELOG.md using git-chglog based on conventional commits.

This command requires git-chglog to be installed. Run 'dev changelog init' first
if you haven't set up the tooling yet.

The changelog is generated from git commit history following the Conventional
Commits specification. Commits should follow the format:
  <type>[optional scope]: <description>

Supported types: feat, fix, docs, refactor, test, perf, build, ci, chore

Examples:
  # Generate full changelog
  dev changelog generate

  # Generate for next version
  dev changelog generate --next v1.2.0

  # Generate for specific tag
  dev changelog generate --tag v1.0.0

  # Output to different file
  dev changelog generate --output CHANGES.md`,
		RunE: func(cmd *cobra.Command, args []string) error {
			output, err := cmd.Flags().GetString("output")
			if err != nil {
				return fmt.Errorf("could not get output flag: %w", err)
			}

			nextVersion, err := cmd.Flags().GetString("next")
			if err != nil {
				return fmt.Errorf("could not get next flag: %w", err)
			}

			tag, err := cmd.Flags().GetString("tag")
			if err != nil {
				return fmt.Errorf("could not get tag flag: %w", err)
			}

			// Check if git-chglog is installed
			if _, err := exec.LookPath("git-chglog"); err != nil {
				slog.Error("git-chglog not found in PATH")
				slog.Info("please install git-chglog first:")
				slog.Info("  go install github.com/git-chglog/git-chglog/cmd/git-chglog@latest")
				slog.Info("or run the init command:")
				slog.Info("  ./dev changelog init")
				return fmt.Errorf("git-chglog not installed: %w", err)
			}

			// Build git-chglog command arguments
			chglogArgs := []string{}

			if nextVersion != "" {
				chglogArgs = append(chglogArgs, "--next-tag", nextVersion)
				slog.Info("generating changelog with next version", "version", nextVersion)
			}

			if output != "" {
				chglogArgs = append(chglogArgs, "--output", output)
			} else {
				chglogArgs = append(chglogArgs, "--output", "CHANGELOG.md")
				output = "CHANGELOG.md"
			}

			if tag != "" {
				chglogArgs = append(chglogArgs, tag)
				slog.Info("generating changelog for specific tag", "tag", tag)
			}

			// Execute git-chglog
			slog.Info("running git-chglog", "args", chglogArgs)
			gitChglog := exec.Command("git-chglog", chglogArgs...)
			gitChglog.Stdout = os.Stdout
			gitChglog.Stderr = os.Stderr

			if err := gitChglog.Run(); err != nil {
				slog.Error("failed to generate changelog", "error", err)
				return fmt.Errorf("failed to generate changelog: %w", err)
			}

			slog.Info("changelog generated successfully", "output", output)
			return nil
		},
	}

	cmd.Flags().String("next", "", "Next version tag (e.g., v1.2.0)")
	cmd.Flags().String("output", "CHANGELOG.md", "Output file path")
	cmd.Flags().String("tag", "", "Generate changelog for specific tag")

	return cmd
}
