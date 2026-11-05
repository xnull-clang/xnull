// Command xnull 是 XNull 工具链命令行入口。
package main

import (
	"fmt"
	"os"
	"os/signal"
	"syscall"

	"xnull.dev/xnull/internal/cli"
	"xnull.dev/xnull/internal/exitcode"
)

func main() {
	signals := make(chan os.Signal, 1)
	signal.Notify(signals, os.Interrupt, syscall.SIGTERM)
	go func() {
		<-signals
		fmt.Fprint(os.Stderr, "\nxnull: 已中断\n")
		os.Exit(exitcode.Interrupted)
	}()

	os.Exit(cli.Run(cli.Env{Stdout: os.Stdout, Stderr: os.Stderr, Args: os.Args[1:]}))
}
