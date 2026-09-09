import re

# Parse CentralDistrict.gd lots
with open(r"D:\geteco\game\CentralDistrict.gd", "r", encoding="utf-8") as f:
    cd_content = f.read()

# Parse Bairro1Expansion.gd roads and lots
with open(r"D:\geteco\game\district\bairro1\Bairro1Expansion.gd", "r", encoding="utf-8") as f:
    b1_content = f.read()

print("Analyzing building lots vs road network...")
