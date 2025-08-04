const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture, mine } = require('@nomicfoundation/hardhat-network-helpers');

const { sum } = require('../../helpers/math');
const { zip } = require('../../helpers/iterate');
const time = require('../../helpers/time');

const { shouldBehaveLikeMultiVotes } = require('./MultiVotes.behaivor');

const MODES = {
  blocknumber: '$MultiVotesMock',
  timestamp: '$MultiVotesTimestampMock',
};

const AMOUNTS = [ethers.parseEther('10000000'), 10n, 20n];

describe('MultiVotes', function () {
  for (const [mode, artifact] of Object.entries(MODES)) {
    const fixture = async () => {
      const accounts = await ethers.getSigners();

      const amounts = Object.fromEntries(
        zip(
          accounts.slice(0, AMOUNTS.length).map(({ address }) => address),
          AMOUNTS,
        ),
      );

      const name = 'Multi delegate votes';
      const version = '1';
      const votes = await ethers.deployContract(artifact, [name, version]);

      return { accounts, amounts, votes, name, version };
    };

    describe(`vote with ${mode}`, function () {
      beforeEach(async function () {
        Object.assign(this, await loadFixture(fixture));
      });

      shouldBehaveLikeMultiVotes(AMOUNTS, { mode, fungible: true });

      //TODO acutal test

    });

  }
});
