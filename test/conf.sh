

release=$1

src=f"$release"-latest.x86_64.qcow2
tag=f"$release"-dracut-sshd-test
dst="$tag".qcow2

key=$PWD/ssh-user

sshflags="-oIdentityFile=$key -oUserKnownHostsFile=$PWD/known_hosts -oUpdateHostKeys=no -oAddKeysToAgent=no"
ssh="ssh $sshflags"
scp="scp $sshflags"

function get_addr
{
    python -c 'import sys; import libvirt; con = libvirt.open("qemu:///system"); dom = con.lookupByName(sys.argv[1]); print(dom.interfaceAddresses(libvirt.VIR_DOMAIN_INTERFACE_ADDRESSES_SRC_LEASE).popitem()[1]["addrs"][-1]["addr"])' "$1"
}

function sync_shutdown
{
    local tag=$1
    virsh --connect qemu:///system shutdown "$tag"
    for ((i=0; i<3; ++i)); do
        if [ "$(virsh --connect qemu:///system domstate "$tag")" = 'shut off' ]; then
            return 0
        fi
        sleep 1
    done
    echo "$tag not shut down in time ..." >&2
    return 1
}

function sync_poweron
{
    local tag=$1
    virsh --connect qemu:///system start "$tag"
    for ((i=0; i<3; ++i)); do
        if [ "$(virsh --connect qemu:///system domstate "$tag")" = running ]; then
            return 0
        fi
        sleep 1
    done
    echo "$tag not started in time ..." >&2
    return 1
}

function wait4sshd
{
    local tag=$1
    sleep 3
    for ((i=0;i<10;++i)); do
        local guest=$(get_addr "$tag")
        if [ "$guest" ]; then
	    echo "$guest $(cat host-key-ed25519.pub)" > known_hosts
	    if [ "$(socat -u -T2 tcp:"$guest":22,connect-timeout=2,readbytes=5 stdout 2>/dev/null)" = "SSH-2" ] && $ssh root@"$guest" uname > /dev/null; then
		echo ' done'
		break
	    fi
        fi
        echo -n .
        sleep 2
    done
    if [ -z "$guest" ]; then
        echo "Couldn't get IP address of guest $tag ..." >&2
        return 1
    fi
    return 0
}
