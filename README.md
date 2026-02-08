[![Unit Tests](https://github.com/cmccomb/okso/actions/workflows/ci-unit.yml/badge.svg)](https://github.com/cmccomb/okso/actions/workflows/ci-unit.yml)
[![Installation Test](https://github.com/cmccomb/okso/actions/workflows/ci-install.yml/badge.svg)](https://github.com/cmccomb/okso/actions/workflows/ci-install.yml)

# `okso`: a local-first agent for macOS

`okso` is a command-line agent native to the modern macOS environment.
It is designed to run all LLMs strictly locally via `llama.cpp`. 
When a user sends a new query `okso` first identifies the general intent of the query, which is used to filter the available toolset.
Next, a dedicated planner generates a structured plan of action before passing it to an executor that runs each step in sequence.
A final validation step ensures that the output is safe and useful before returning it to the user. If not, the agent can re-plan and try again.

Ultimately, this system is designed to be a robust, useful, local daily driver.

## Installation

The tool is distributed via Homebrew. This manages dependencies and adds the CLI to your path.

```sh
brew tap cmccomb/okso https://github.com/cmccomb/okso
brew install --HEAD cmccomb/okso/okso
```

To update or remove:

```sh
brew upgrade okso
brew uninstall okso
```


## Basic usage

Run `okso` followed by your request.
The agent will propose a sequence of steps using its [tool registry](http://cmccomb.com/okso/reference/tools.html), 
including a persistent terminal, sandboxed Python REPL, and macOS-native applications (Notes, Reminders, Calendar)

If you don't need any special characters, you can skip the quotes:
```sh
okso what time is my next meeting at -y -vvv
```

But if you need special characters, use quotes:
```sh
okso "can you rephrase this question more accurately? 'What is the capital of that place in europe?'"
```

For more detailed usage guidance, read the [documentation](http://cmccomb.com/okso).
For maintainer, support, and roadmap details, see [Project](docs/project.md).
