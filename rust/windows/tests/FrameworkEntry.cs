// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

using System;
using System.Globalization;
using System.Runtime.InteropServices;

[assembly: ComVisible(true)]

namespace PowerShellNative.Tests
{
    [ClassInterface(ClassInterfaceType.AutoDual)]
    public sealed class FrameworkEntry
    {
        public int Start(string consoleFile, string[] arguments)
        {
            string[] expected = { "", "two words", "quote\"value", "trailing\\", "\u03bb\ud83d\ude00" };
            if (arguments.Length != expected.Length)
            {
                throw new ArgumentException("Argument count was not preserved.");
            }
            for (int index = 0; index < expected.Length; index++)
            {
                if (!String.Equals(arguments[index], expected[index], StringComparison.Ordinal))
                {
                    throw new ArgumentException("Argument " + index + " was not preserved.");
                }
            }
            return Int32.Parse(consoleFile, CultureInfo.InvariantCulture);
        }
    }
}
