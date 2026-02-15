[CCode (cheader_filename = "cert_gen.h")]
namespace CertGen {
    [CCode (cname = "dinox_generate_self_signed_cert")]
    public int generate_self_signed_cert(string cert_path, string key_path, string cn);

    [CCode (cname = "dinox_check_cert_valid")]
    public int check_cert_valid(string cert_path);

    [CCode (cname = "dinox_delete_cert")]
    public int delete_cert(string cert_path, string key_path);
}
