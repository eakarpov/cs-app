"""Static APK acceptance only: does not install, launch, upload or alter devices."""
import argparse,hashlib,json,re,subprocess,zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser();p.add_argument('--apk',required=True);p.add_argument('--kind',choices=['release','preview'],required=True);p.add_argument('--sdk',required=True);p.add_argument('--out',required=True);p.add_argument('--previous');a=p.parse_args()
sdk=Path(a.sdk);aapt=sdk/'build-tools/34.0.0/aapt';signer=sdk/'build-tools/34.0.0/apksigner'
version=re.search(r'^version:\s*(\S+)',(ROOT/'pubspec.yaml').read_text(),re.M)[1];name,code=version.split('+');code=int(code)
assert f"const appVersion = '{name}';" in (ROOT/'lib/core/app_version.dart').read_text()
def info(path):
 badging=subprocess.check_output([str(aapt),'dump','badging',str(path)],text=True)
 signed=subprocess.check_output([str(signer),'verify','--verbose','--print-certs',str(path)],text=True)
 match=re.search(r"package: name='([^']+)' versionCode='(\d+)' versionName='([^']+)'",badging);assert match
 digest=re.search(r'Signer #1 certificate SHA-256 digest: ([0-9a-f]+)',signed)[1]
 return {'packageId':match[1],'versionCode':int(match[2]),'versionName':match[3],'label':re.search(r"application-label:'([^']+)'",badging)[1],'minSdk':int(re.search(r"sdkVersion:'(\d+)'",badging)[1]),'targetSdk':int(re.search(r"targetSdkVersion:'(\d+)'",badging)[1]),'debuggable':'application-debuggable' in badging,'certificateSha256':digest,'signatureVerified':True,'nativeCode':re.search(r'native-code: (.+)',badging)[1].strip()}
apk=Path(a.apk);result=info(apk);expected_package='info.typikon.cs'+('.preview' if a.kind=='preview' else '')
assert result['packageId']==expected_package and result['versionName']==name and result['versionCode']==code
assert result['debuggable']==(a.kind=='preview')
assert result['label']==('Лексикон ЦС · проверка' if a.kind=='preview' else 'Лексикон ЦС')
if a.kind=='release':assert result['certificateSha256']=='efbd5403c1bf73c63e8feac9f95b71b2231c96e7d39c8f2be6a153089a8398f8'
endpoint=b'https://www.typikon.info/api/v2/cs/'
with zipfile.ZipFile(apk) as z:
 entries=z.namelist();assert not any(x.lower().endswith(('.sqlite','.sqlite3','.db','.jks','.keystore','.p12','.pem')) for x in entries)
 compiled=[x for x in entries if x.endswith('/libapp.so') or x=='assets/flutter_assets/kernel_blob.bin'];assert compiled
 assert any(endpoint in z.read(x) for x in compiled)
result.update({'status':'passed','kind':a.kind,'path':str(apk.resolve()),'sha256':hashlib.file_digest(apk.open('rb'),'sha256').hexdigest(),'bytes':apk.stat().st_size,'sourceVersion':version,'serverHttpsStringPresent':True,'dictionaryOrPrivateKeyBundled':False,'installed':False,'launched':False,'visualChecked':False})
if a.previous:
 previous=info(Path(a.previous));assert previous['packageId']==result['packageId'] and previous['certificateSha256']==result['certificateSha256'] and previous['versionCode']<result['versionCode'];result['previousApk']={'path':a.previous,'versionName':previous['versionName'],'versionCode':previous['versionCode'],'samePackageAndCertificate':True};result['nativeUpgradeTested']=False
Path(a.out).write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n');print(json.dumps({k:result[k] for k in ['status','kind','packageId','versionName','versionCode','sha256']}))
