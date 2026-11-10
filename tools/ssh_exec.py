import os,sys,argparse
HOST=os.environ.get("GR_HOST","172.18.101.202")
USER=os.environ.get("GR_USER","luoji")
PASS=os.environ.get("GR_PASS","P@ssw0rdlj")
def shq(s): return "'" + s.replace("'","'\"'\"'") + "'"
ap=argparse.ArgumentParser()
ap.add_argument("command",nargs="?",default="echo ok")
ap.add_argument("--docker",default=None)
ap.add_argument("--timeout",type=float,default=1800.0)
a=ap.parse_args()
try:
    import paramiko
except ImportError:
    sys.stderr.write("MISSING paramiko\n"); sys.exit(127)
cmd=a.command
if a.docker: cmd="docker exec "+shq(a.docker)+" bash -lc "+shq(cmd)
cli=paramiko.SSHClient(); cli.set_missing_host_key_policy(paramiko.AutoAddPolicy())
cli.connect(HOST,port=22,username=USER,password=PASS,timeout=25,banner_timeout=40,auth_timeout=40,look_for_keys=False,allow_agent=False)
i,o,e=cli.exec_command(cmd,timeout=a.timeout)
so=o.read().decode("utf-8","replace"); se=e.read().decode("utf-8","replace"); rc=o.channel.recv_exit_status()
cli.close()
sys.stdout.write(so)
if se.strip(): sys.stderr.write("\n-- stderr --\n"+se)
sys.stdout.write("\n-- exit %d --\n"%rc)
sys.exit(rc)
