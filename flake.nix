{
  description = "officetv: run and control an Android TV (Waydroid) session";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      officetv = pkgs.writeShellApplication {
        name = "officetv";
        # waydroid itself comes from the host's package manager.
        runtimeInputs = with pkgs; [ android-tools coreutils gnugrep gnused gawk util-linux ];
        text = builtins.readFile ./officetv;
      };
    in {
      packages.${system}.default = officetv;

      apps.${system}.default = {
        type = "app";
        program = "${officetv}/bin/officetv";
      };

      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [ android-tools scrcpy shellcheck ];
      };
    };
}
