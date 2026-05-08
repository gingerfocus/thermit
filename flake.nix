{
  inputs.nixpkgs.url = "nixpkgs-unstable"; # "nixpkgs";

  inputs.zig.url = "github:mitchellh/zig-overlay/6f9a3c160daca2a701a638a7ea7b0e675c1a1848";
  inputs.zig.inputs.nixpkgs.follows = "nixpkgs";

  outputs = {
    self,
    nixpkgs,
    zig,
  }: let
    lib = nixpkgs.lib;
    systems = ["aarch64-linux" "x86_64-linux"];
    eachSystem = f:
      lib.foldAttrs lib.mergeAttrs {}
      (map (s: lib.mapAttrs (_: v: {${s} = v;}) (f s)) systems);
  in
    eachSystem (system: let
      pkgs = import nixpkgs {inherit system;};
    in {
      devShells.default = pkgs.mkShell {
        packages = with pkgs; [
          zig.packages."${system}".master
        ];
      };

      formatter = pkgs.alejandra;

      packages = {};
    });
}
