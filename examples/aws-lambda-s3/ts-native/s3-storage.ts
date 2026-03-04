/**
 * S3 Storage adapter for vcdb
 */
import {
  S3Client,
  GetObjectCommand,
  PutObjectCommand,
  DeleteObjectCommand,
  HeadObjectCommand,
  ListObjectsV2Command,
} from '@aws-sdk/client-s3';

const s3 = new S3Client({});

export interface StorageAdapter {
  read(path: string): Promise<Uint8Array | null>;
  write(path: string, data: Uint8Array): Promise<void>;
  delete(path: string): Promise<void>;
  exists(path: string): Promise<boolean>;
  list(prefix?: string): Promise<string[]>;
}

export function createS3Storage(bucket: string, prefix = ''): StorageAdapter {
  const makeKey = (path: string) => (prefix ? `${prefix}/${path}` : path);

  return {
    async read(path: string) {
      try {
        const res = await s3.send(new GetObjectCommand({
          Bucket: bucket,
          Key: makeKey(path),
        }));
        return new Uint8Array(await res.Body!.transformToByteArray());
      } catch (e: any) {
        if (e.name === 'NoSuchKey') return null;
        throw e;
      }
    },

    async write(path: string, data: Uint8Array) {
      await s3.send(new PutObjectCommand({
        Bucket: bucket,
        Key: makeKey(path),
        Body: data,
      }));
    },

    async delete(path: string) {
      await s3.send(new DeleteObjectCommand({
        Bucket: bucket,
        Key: makeKey(path),
      }));
    },

    async exists(path: string) {
      try {
        await s3.send(new HeadObjectCommand({
          Bucket: bucket,
          Key: makeKey(path),
        }));
        return true;
      } catch {
        return false;
      }
    },

    async list(subPrefix = '') {
      const fullPrefix = prefix ? `${prefix}/${subPrefix}` : subPrefix;
      const res = await s3.send(new ListObjectsV2Command({
        Bucket: bucket,
        Prefix: fullPrefix,
      }));
      return (res.Contents || []).map(o => o.Key!);
    },
  };
}
