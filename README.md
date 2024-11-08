# Nym Node Deployment

This guide will help you set up and run a [Nym node](https://nymtech.net/) on your server. Nym is a privacy-focused network that provides anonymity for users and applications.

## Table of Contents

- [Nym Node Deployment](#nym-node-deployment)
  - [Table of Contents](#table-of-contents)
  - [Prerequisites](#prerequisites)
  - [Installation](#installation)
  - [Configuration](#configuration)
  - [Usage](#usage)
  - [Troubleshooting](#troubleshooting)
  - [Contributing](#contributing)
  - [License](#license)

## Prerequisites

Before you begin, ensure you have the following:

- A server running a compatible Linux distribution (e.g., Ubuntu).
- Root access to the server.
- Basic knowledge of command-line operations.
- Ansible installed on your local machine for deployment.

## Installation

1. **Clone the Repository**

   First, clone this repository to your local machine:

   ```bash
   git clone https://github.com/spectreintern/nym-node-ansible.git
   cd nym-node-ansible
   ```

2. **Update Inventory**

   Open the `inventory.ini` file and update it with your server details. For example:

   ```ini
   [nymnodes]
   node1 ansible_host=YOUR_SERVER_IP ansible_user=root hostname=your.hostname.com location=YourLocation email=your.email@example.com
   ```

3. **Update Landing Page**

   Update the landing page in `roles/nginx/templates/landing.html.j2` to suite your needs. An example can be found in [Nym docs
   ](https://nymtech.net/docs/operators/nodes/nym-node/configuration/proxy-configuration#html-file-customization)

4. **Run the Playbook**

   Execute the Ansible playbook to install and configure the Nym node:

   ```bash
   ansible-playbook -i inventory.ini install.yml
   ```

   This command will install the necessary packages, download the Nym binaries, and set up the Nym node service.

## Configuration


The configuration for the node version and your DAO name can be found in the `group_vars/all.yml` file. You can modify the following variables:

- `nym_version`: The version of the Nym binaries to install.
<<<<<<< HEAD
- `binary_url`: The URL to download the Nym node binary.
- `cli_url`: The URL to download the Nym cli binary.
- `tunnel_manager_url`: The URL to download the tunnel manager script.
=======
- `dao_name`: The name of the DAO / organization / project running the node.
>>>>>>> 5c919ca (add announce_wss_port, landing page and enhanced README)

## Usage

Once the installation is complete, the Nym node will be running as a systemd service. You can manage the service using the following commands:

- **Stop the Nym Node:**

  ```bash
  systemctl stop nym-node
  ```

- **Check the Status:**

  ```bash
  systemctl status nym-node
  ```

- **View Logs:**

  ```bash
  journalctl -u nym-node -f
  ```

## Troubleshooting

If you encounter any issues during installation or while running the Nym node, consider the following steps:

- Check the logs for any error messages using the command above.
- Ensure that all required ports are open in your firewall (UFW).
- Verify that the server meets the prerequisites listed above.

## Contributing

Contributions are welcome! If you have suggestions for improvements or find bugs, please open an issue or submit a pull request.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
