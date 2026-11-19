# Poppler 25.03 (Debian 13) can sign but cannot say why signing failed (25.05+ API).
f=$(echo signed-*/src/signer.cpp)
expect "$f" 'using SR = Poppler::PDFConverter::SigningResult'
perl -0pi -e 's/        using SR = .*?return \{false, false, tr\("signing failed"\)\};\n        \}\n        \}\n/        return {false, false, tr("signing failed")};  \/\/ Debian port: no signing result details on Poppler 25.03\n/s' "$f"
! grep -q 'lastSigningResult' "$f"
