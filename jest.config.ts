import type { Config } from "jest";
import createJestConfig from "next/jest";

const customJestConfig: Config = {
  setupFilesAfterEnv: ["<rootDir>/__tests__/setup.ts"],
  testEnvironment: "jest-environment-jsdom",
  preset: "ts-jest",
  moduleNameMapper: {
    "^@/(.*)$": "<rootDir>/$1",
  },
  transform: {
    "^.+\\.tsx?$": "ts-jest",
  },
};

const nextJestConfig = createJestConfig({
  dir: ".",
});

const config = async () => {
  const config = await nextJestConfig(customJestConfig);
  return config;
};

export default config;
