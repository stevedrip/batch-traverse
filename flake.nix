{
  description = "batch-traverse";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-ruby.url = "github:bobvanderlinden/nixpkgs-ruby";
    nixpkgs-ruby.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, nixpkgs-ruby }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
    in
    {
      devShells = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          ruby = nixpkgs-ruby.lib.packageFromRubyVersionFile {
            file = ./.ruby-version;
            inherit system;
          };
        in
        {
          # sqlite/openssl/libyaml back the native extensions bundler needs to
          # build for sqlite3 (AR's test adapter) and its usual dependencies.
          default = pkgs.mkShell {
            packages = [ ruby pkgs.bundler pkgs.sqlite pkgs.openssl pkgs.libyaml ];
          };
        });
    };
}
