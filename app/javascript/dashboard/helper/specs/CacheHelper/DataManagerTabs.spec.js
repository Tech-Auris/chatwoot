import { DataManager } from '../../CacheHelper/DataManager';

// Logging out deletes the account's cache database. When another tab of the
// panel still holds it open, the deletion waits for that tab, and every new
// open of the database queues behind the deletion: the inbox list of the new
// session never loaded ("Carregando caixas de entrada" forever).
describe('DataManager with two tabs open', () => {
  const accountId = 'two-tabs';
  const settlesWithin = (promise, ms) =>
    Promise.race([
      promise.then(() => true),
      new Promise(resolve => {
        setTimeout(() => resolve(false), ms);
      }),
    ]);

  it('lets another tab delete the cache on logout and open it again', async () => {
    const otherTab = new DataManager(accountId);
    await otherTab.initDb();

    const deletion = new Promise(resolve => {
      window.indexedDB.deleteDatabase(`cw-store-${accountId}`).onsuccess =
        resolve;
    });
    expect(await settlesWithin(deletion, 500)).toBe(true);

    const newSession = new DataManager(accountId);
    expect(await settlesWithin(newSession.initDb(), 500)).toBe(true);
  });
});
