// Names every Detox artifact (screenshot, video, log) per Bitrise's
// <classname>__<name>__<label>.<ext> attachment convention, the same way
// jest-junit names the test case with its default settings (both the
// classname and name parts use the same cleaned full test title).
// https://docs.bitrise.io/en/bitrise-ci/testing/test-reports/test-attachments/naming-attachments-after-test-cases
const path = require('path');

const clean = (value) => value.replace(/["*/:<>?\\|]/g, '_');

module.exports = class BitrisePathBuilder {
  constructor({ rootDir }) {
    this.rootDir = rootDir;
  }

  buildPathForTestArtifact(artifactName, testSummary) {
    if (!testSummary) return path.join(this.rootDir, artifactName);

    const { title, fullName } = testSummary;
    const key = clean(`${fullName.slice(0, -title.length).trim()} ${title}`);
    const ext = path.extname(artifactName);
    const label = path.basename(artifactName, ext).replace(/_+/g, '_').replace(/^_/, '');
    return path.join(this.rootDir, `${key}__${key}__${label}${ext}`);
  }
};
