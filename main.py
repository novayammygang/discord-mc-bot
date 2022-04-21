import discord
from discord.ext import commands
import requests

bot = commands.Bot(command_prefix='>', description="This is the Minecraft slave bot")
api_endpoint = ''
token = ''


@bot.command(name="stop")
async def stop(ctx, *, name):
    response = requests.urlopen(api_endpoint + 'instance_functions?name=minecraft&state=stop')
    print(response.text)

    await ctx.send(response.text)

@bot.command(name="start")
async def start(ctx, *, name):
    response = requests.get(api_endpoint + 'instance_functions?name=minecraft&state=start')
    print(response.text)

    await ctx.send(response.text)

bot.run(token)