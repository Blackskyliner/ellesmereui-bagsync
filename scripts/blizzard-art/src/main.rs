//! Pins Blizzard UI textures to byte ranges on Blizzard's CDN.
//!
//!   blizzard-art --listfile CSV --paths FILE --out LOCK [--cache DIR] [--product NAME]
//!
//! Reads WoW texture paths (one per line, as the addons and FrameXML request
//! them), maps them to file data IDs with the simulator's listfile, and
//! resolves each one through the current build of the product (`wow` for
//! retail, the default; `wowf` for WoW Forever): root (file data ID ->
//! content key), encoding (content key -> encoding key) and the archive
//! indices (encoding key -> archive, offset, size). The lock it writes holds
//! only these keys and offsets; scripts/blizzard-art.py fetches the files.
//! Build manifests and indices are cached, since they total some 400 MB.

use cascette_crypto::md5::{ContentKey, FileDataId};
use cascette_formats::archive::ArchiveIndex;
use cascette_formats::CascFormat;
use cascette_formats::blte::BlteFile;
use cascette_formats::config::{BuildConfig, CdnConfig};
use cascette_formats::encoding::EncodingFile;
use cascette_formats::root::{LocaleFlags, RootFile};
use reqwest::blocking::Client;
use serde::Serialize;
use std::collections::{BTreeMap, HashMap, HashSet};
use std::io::Cursor;
use std::path::{Path, PathBuf};
use std::sync::Mutex;

const PATCH: &str = "http://us.patch.battle.net:1119";
const CDN: &str = "https://us.cdn.blizzard.com/tpr/wow";

type Error = Box<dyn std::error::Error + Send + Sync>;

#[derive(Serialize)]
struct Lock {
    schema: u32,
    product: String,
    version: String,
    build_config: String,
    cdn_config: String,
    files: Vec<LockedFile>,
}

#[derive(Serialize)]
struct LockedFile {
    path: String,
    file_data_id: u32,
    content_key: String,
    content_size: u64,
    encoding_key: String,
    /// None: the file lies loose on the CDN under its encoding key.
    archive: Option<String>,
    offset: u64,
    size: u64,
}

struct Args {
    listfile: PathBuf,
    paths: PathBuf,
    out: PathBuf,
    cache: PathBuf,
    product: String,
}

fn parse_args() -> Result<Args, Error> {
    let mut map = HashMap::new();
    let mut it = std::env::args().skip(1);
    while let Some(key) = it.next() {
        let value = it.next().ok_or_else(|| format!("{key} needs a value"))?;
        map.insert(key, PathBuf::from(value));
    }
    let mut take = |k: &str| map.remove(k).ok_or_else(|| format!("missing {k}"));
    let listfile = take("--listfile")?;
    let paths = take("--paths")?;
    let out = take("--out")?;
    let cache = map
        .remove("--cache")
        .unwrap_or_else(|| PathBuf::from(".tools/blizzard-cdn"));
    let product = map
        .remove("--product")
        .map_or_else(|| "wow".to_string(), |p| p.to_string_lossy().into_owned());
    Ok(Args { listfile, paths, out, cache, product })
}

fn main() -> Result<(), Error> {
    let args = parse_args()?;
    let client = Client::builder()
        .timeout(std::time::Duration::from_secs(300))
        .build()?;
    std::fs::create_dir_all(&args.cache)?;

    let (version, build_hash, cdn_hash) = current_build(&client, &args.product)?;
    eprintln!("build {version} (build config {build_hash}, CDN config {cdn_hash})");

    let wanted = map_paths(&args.listfile, &args.paths)?;
    eprintln!("{} paths map to {} files", wanted.requested, wanted.files.len());
    for miss in &wanted.missing {
        eprintln!("not in the listfile: {miss}");
    }

    let build = BuildConfig::parse(Cursor::new(config(&client, &args.cache, &build_hash)?))
        .map_err(|e| e.to_string())?;
    let cdn = CdnConfig::parse(Cursor::new(config(&client, &args.cache, &cdn_hash)?))
        .map_err(|e| e.to_string())?;

    let encoding_info = build.encoding().ok_or("build config has no encoding")?;
    let encoding_ekey = encoding_info
        .encoding_key
        .ok_or("build config has no encoding key")?;
    eprintln!("loading encoding");
    let encoding = EncodingFile::parse_blte(&data(&client, &args.cache, &encoding_ekey)?)?;

    let root_ckey = ContentKey::from_hex(build.root().ok_or("build config has no root")?)?;
    let root_ekey = encoding
        .find_encoding(&root_ckey)
        .ok_or("root content key missing from encoding")?;
    eprintln!("loading root");
    let root_blte = data(&client, &args.cache, &root_ekey.to_hex())?;
    let root = RootFile::parse(&BlteFile::parse(&root_blte).map_err(|e| e.to_string())?.decompress()?)?;

    let mut resolved = Vec::new();
    let mut ekeys = HashSet::new();
    for (fdid, path) in &wanted.files {
        let Some(entries) = root.get_entries_by_id(FileDataId::new(*fdid)) else {
            eprintln!("not in root: {fdid} {path}");
            continue;
        };
        let entry = entries
            .iter()
            .find(|e| e.locale_flags.has(LocaleFlags::ENUS))
            .unwrap_or(&entries[0]);
        let Some(ekey) = encoding.find_encoding(&entry.content_key) else {
            eprintln!("not in encoding: {fdid} {path}");
            continue;
        };
        let size = content_size(&encoding, &entry.content_key);
        let ekey = ekey.to_hex();
        ekeys.insert(ekey.clone());
        resolved.push((*fdid, path.clone(), entry.content_key.to_hex(), size, ekey));
    }

    let located = locate(&client, &args.cache, &cdn, &ekeys)?;
    let mut files = Vec::new();
    for (fdid, path, ckey, content_size, ekey) in resolved {
        let (archive, offset, size) = match located.get(&ekey) {
            Some((archive, offset, size)) => (Some(archive.clone()), *offset, *size),
            None => (None, 0, encoded_size(&encoding, &ekey)?),
        };
        files.push(LockedFile {
            path,
            file_data_id: fdid,
            content_key: ckey,
            content_size,
            encoding_key: ekey,
            archive,
            offset,
            size,
        });
    }
    files.sort_by(|a, b| a.path.to_ascii_lowercase().cmp(&b.path.to_ascii_lowercase()));

    let lock = Lock {
        schema: 1,
        product: args.product.clone(),
        version,
        build_config: build_hash,
        cdn_config: cdn_hash,
        files,
    };
    std::fs::write(&args.out, serde_json::to_string_pretty(&lock)? + "\n")?;
    eprintln!("wrote {} files to {}", lock.files.len(), args.out.display());
    Ok(())
}

fn current_build(client: &Client, product: &str) -> Result<(String, String, String), Error> {
    let url = format!("{PATCH}/{product}/versions");
    let text = client.get(url).send()?.error_for_status()?.text()?;
    let line = text
        .lines()
        .find(|l| l.starts_with("us|"))
        .ok_or("no us region in the versions")?;
    let cols: Vec<&str> = line.split('|').collect();
    Ok((cols[5].to_string(), cols[1].to_string(), cols[2].to_string()))
}

struct Wanted {
    requested: usize,
    files: BTreeMap<u32, String>,
    missing: Vec<String>,
}

/// Listfile paths are matched without extension and case, with and without
/// the leading Interface/, the way the simulator resolves a texture path.
fn map_paths(listfile: &Path, paths: &Path) -> Result<Wanted, Error> {
    let mut by_path: HashMap<String, (u32, String)> = HashMap::new();
    for line in std::fs::read_to_string(listfile)?.lines() {
        let Some((id, path)) = line.split_once(';') else { continue };
        let Ok(id) = id.trim().parse::<u32>() else { continue };
        let lower = path.trim().to_ascii_lowercase();
        let Some(stem) = lower.strip_suffix(".blp").or_else(|| lower.strip_suffix(".tga")) else {
            continue;
        };
        by_path.entry(stem.to_string()).or_insert((id, path.trim().to_string()));
    }
    let mut wanted = Wanted { requested: 0, files: BTreeMap::new(), missing: Vec::new() };
    for line in std::fs::read_to_string(paths)?.lines() {
        let raw = line.trim();
        if raw.is_empty() {
            continue;
        }
        wanted.requested += 1;
        let mut key = raw.replace('\\', "/").to_ascii_lowercase();
        for ext in [".blp", ".tga"] {
            if let Some(stem) = key.strip_suffix(ext) {
                key = stem.to_string();
            }
        }
        let hit = by_path
            .get(&key)
            .or_else(|| by_path.get(&format!("interface/{key}")));
        match hit {
            Some((id, path)) => {
                wanted.files.insert(*id, path.clone());
            }
            None => wanted.missing.push(raw.to_string()),
        }
    }
    Ok(wanted)
}

fn content_size(encoding: &EncodingFile, ckey: &ContentKey) -> u64 {
    encoding
        .ckey_pages
        .iter()
        .flat_map(|p| p.entries.iter())
        .find(|e| e.content_key == *ckey)
        .map(|e| e.file_size)
        .unwrap_or(0)
}

/// Encoding key -> (archive, offset, size), from all archive indices of the
/// CDN config. Only the wanted keys are kept.
fn locate(
    client: &Client,
    cache: &Path,
    cdn: &CdnConfig,
    ekeys: &HashSet<String>,
) -> Result<HashMap<String, (String, u64, u64)>, Error> {
    let archives: Vec<String> = cdn.archives().into_iter().map(|a| a.content_key).collect();
    eprintln!("scanning {} archive indices", archives.len());
    let found = Mutex::new(HashMap::new());
    let next = Mutex::new(0usize);
    let failure: Mutex<Option<String>> = Mutex::new(None);
    std::thread::scope(|scope| {
        for _ in 0..8 {
            scope.spawn(|| loop {
                let i = {
                    let mut n = next.lock().unwrap();
                    let i = *n;
                    *n += 1;
                    i
                };
                let Some(archive) = archives.get(i) else { break };
                let result = data(client, cache, &format!("{archive}.index"))
                    .and_then(|raw| ArchiveIndex::parse(Cursor::new(raw)).map_err(Error::from));
                match result {
                    Ok(index) => {
                        let mut found = found.lock().unwrap();
                        for e in index.entries {
                            let key = hex::encode(&e.encoding_key);
                            if ekeys.contains(&key) {
                                found.insert(key, (archive.clone(), e.offset, u64::from(e.size)));
                            }
                        }
                    }
                    Err(err) => {
                        *failure.lock().unwrap() = Some(format!("{archive}.index: {err}"));
                        break;
                    }
                }
            });
        }
    });
    if let Some(err) = failure.into_inner().unwrap() {
        return Err(err.into());
    }
    Ok(found.into_inner().unwrap())
}

/// Size of a file that lies loose on the CDN, from the encoding file's
/// encoding-key pages.
fn encoded_size(encoding: &EncodingFile, ekey: &str) -> Result<u64, Error> {
    encoding
        .ekey_pages
        .iter()
        .flat_map(|p| p.entries.iter())
        .find(|e| e.encoding_key.to_hex() == ekey)
        .map(|e| e.file_size)
        .ok_or_else(|| format!("no size for loose file {ekey}").into())
}

fn cdn_url(kind: &str, name: &str) -> String {
    format!("{CDN}/{kind}/{}/{}/{name}", &name[..2], &name[2..4])
}

fn config(client: &Client, cache: &Path, hash: &str) -> Result<Vec<u8>, Error> {
    cached(client, cache, "config", hash)
}

fn data(client: &Client, cache: &Path, name: &str) -> Result<Vec<u8>, Error> {
    cached(client, cache, "data", name)
}

fn cached(client: &Client, cache: &Path, kind: &str, name: &str) -> Result<Vec<u8>, Error> {
    let file = cache.join(kind).join(name);
    if let Ok(bytes) = std::fs::read(&file) {
        return Ok(bytes);
    }
    let bytes = client.get(cdn_url(kind, name)).send()?.error_for_status()?.bytes()?.to_vec();
    std::fs::create_dir_all(file.parent().unwrap())?;
    let tmp = file.with_extension("part");
    std::fs::write(&tmp, &bytes)?;
    std::fs::rename(&tmp, &file)?;
    Ok(bytes)
}
