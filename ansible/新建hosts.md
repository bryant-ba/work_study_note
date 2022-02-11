新建ansible hosts
---

    [k8s]
    master ansible_host=192.168.88.128 ansible_port=22 ansible_user=root ansible_ssh_pass='1234qwer'
    node1 ansible_host=192.168.88.129 ansible_port=22 ansible_user=root ansible_ssh_pass='1234qwer'
    node2 ansible_host=192.168.88.130 ansible_port=22 ansible_user=root ansible_ssh_pass='1234qwer'

需要加上ansible_host,ansible_port,ansible_user,ansible_ssh_pass 参数
