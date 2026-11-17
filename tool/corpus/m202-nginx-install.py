from pathlib import Path
import subprocess,shutil
root=Path('/var/www/typikon.su/typikon-web-releases/incoming')
site=Path('/etc/nginx/sites-enabled/typikon').resolve()
zone=Path('/etc/nginx/conf.d/typikon-reader-zone.conf')
locations=Path('/etc/nginx/snippets/typikon-reader-locations.conf')
backup=root/'m202-nginx-before.conf'
if not backup.exists():shutil.copy2(site,backup)
original=site.read_text()
try:
    zone.write_bytes((root/zone.name).read_bytes())
    locations.write_bytes((root/locations.name).read_bytes())
    include='    include snippets/typikon-reader-locations.conf;'
    if include not in original:
        anchor='    include snippets/typikon-cs-dictionary-locations.conf;'
        assert original.count(anchor)==1
        site.write_text(original.replace(anchor,anchor+'\n'+include))
    subprocess.run(['nginx','-t'],check=True)
    subprocess.run(['systemctl','reload','nginx'],check=True)
except Exception:
    site.write_text(original)
    zone.unlink(missing_ok=True);locations.unlink(missing_ok=True)
    subprocess.run(['nginx','-t'],check=True)
    raise
print('Scoped reader/index edge ceiling installed: 10r/s burst20; OPTIONS exempt')
